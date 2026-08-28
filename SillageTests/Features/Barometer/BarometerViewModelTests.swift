//
//  BarometerViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
import CoreMotion
import Synchronization
import Clocks
@testable import Sillage

@MainActor
@Suite("Barometer View Model Tests", .serialized)
final class BarometerViewModelTests {
  final class TestDateBox: Sendable {
    let mutex: Mutex<Date>
    init(initialDate: Date) {
      self.mutex = Mutex(initialDate)
    }
  }
  
  let dbManager: DatabaseManager
  let store: BarometricHistoryStore
  let preferencesService: PreferencesService
  let notificationService: LocalNotificationService
  let permissionService: PermissionService
  let positioningService: CoreLocationPositioningService
  let barometricService: BarometricService
  let testClock: TestClock<Duration>
  let simulatedNow: TestDateBox
  let viewModel: BarometerViewModel
  
  init() throws {
    let clock = TestClock()
    let nowBox = TestDateBox(initialDate: Date(timeIntervalSince1970: 1_700_000_000))
    self.testClock = clock
    self.simulatedNow = nowBox
    let dateProvider: @Sendable () -> Date = { nowBox.mutex.withLock { $0 } }
    
    dbManager = try DatabaseManager.inMemory()
    store = BarometricHistoryStore(databaseManager: dbManager, dateProvider: dateProvider)
    preferencesService = PreferencesService()
    notificationService = LocalNotificationService()
    positioningService = CoreLocationPositioningService(initialAccuracyMode: .best)
    permissionService = PermissionService(
      positioningService: positioningService,
      notificationService: notificationService
    )
    barometricService = BarometricService(
      historyStore: store,
      preferencesService: preferencesService,
      notificationService: notificationService,
      permissionService: permissionService,
      dateProvider: dateProvider
    )
    self.viewModel = BarometerViewModel(
      service: barometricService,
      preferencesService: preferencesService,
      clock: clock,
      dateProvider: dateProvider
    )
  }
  
  @Test("Debounced refresh cancels preceding rapid requests")
  func testDebouncedRefreshCancelsPrecedingRequests() async throws {
    let now = simulatedNow.mutex.withLock { $0 }
    
    // Add readings at -1h and -5h
    let r1 = BarometricReading(timestamp: now.addingTimeInterval(-3600), pressure: Measurement(value: 1010.0, unit: .hectopascals))
    let r2 = BarometricReading(timestamp: now.addingTimeInterval(-5 * 3600), pressure: Measurement(value: 1015.0, unit: .hectopascals))
    
    await store.add(reading: r2)
    await store.add(reading: r1)
    
    // Trigger rapid debounced calls
    let intervalOld = DateInterval(start: now.addingTimeInterval(-6 * 3600), end: now.addingTimeInterval(-4 * 3600))
    let intervalRecent = DateInterval(start: now.addingTimeInterval(-2 * 3600), end: now)
    
    viewModel.refreshHistoryDebounced(in: intervalOld)
    viewModel.refreshHistoryDebounced(in: intervalRecent)
    
    // Virtual advance through test clock to trigger debounce timer deterministically
    await testClock.advance(by: .milliseconds(150))
    
    // Deterministically await completion of the active fetch task
    await viewModel.waitUntilIdle()
    
    // Only the second request (intervalRecent with r1) should have been loaded
    #expect(viewModel.history24h.count == 1)
    #expect(viewModel.history24h.first?.pressure.value == 1010.0)
  }
  
  @Test("Latest timestamp remains anchored to current time when querying past history")
  func testLatestTimestampRemainsAnchoredToPresentWhenLoadingPastHistory() async throws {
    let now = simulatedNow.mutex.withLock { $0 }
    let anchorBeforeQuery = viewModel.latestTimestamp
    
    // Add readings 4 days in the past
    let pastDate = now.addingTimeInterval(-4 * 24 * 3600)
    let pastReading = BarometricReading(timestamp: pastDate, pressure: Measurement(value: 1013.25, unit: .hectopascals))
    await store.add(reading: pastReading)
    
    // Query historical window from 5 days ago to 3 days ago
    let pastInterval = DateInterval(
      start: now.addingTimeInterval(-5 * 24 * 3600),
      end: now.addingTimeInterval(-3 * 24 * 3600)
    )
    await viewModel.refreshHistory(in: pastInterval)
    
    // The chart data should be populated with the past reading
    #expect(viewModel.chartData.count == 1)
    if let firstTimestamp = viewModel.chartData.first?.reading.timestamp {
      #expect(abs(firstTimestamp.timeIntervalSince(pastDate)) < 0.01)
    }
    
    // Crucially, latestTimestamp MUST NOT be shifted to the past date
    #expect(viewModel.latestTimestamp == anchorBeforeQuery)
  }
  
  @Test("Update latest timestamp refreshes anchor to current time")
  func testUpdateLatestTimestampRefreshesAnchor() async throws {
    let before = simulatedNow.mutex.withLock { $0 }
    #expect(viewModel.latestTimestamp == before)
    
    let advancedDate = before.addingTimeInterval(3600)
    simulatedNow.mutex.withLock { $0 = advancedDate }
    viewModel.updateLatestTimestamp()
    
    #expect(viewModel.latestTimestamp == advancedDate)
  }
  
  @Test("Day label formats Today, Yesterday, and past days properly")
  func testDayLabelFormatting() async throws {
    let now = simulatedNow.mutex.withLock { $0 }
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    
    let todayLabel = viewModel.dayLabel(for: today)
    #expect(todayLabel == "Today")
    
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
      let yesterdayLabel = viewModel.dayLabel(for: yesterday)
      #expect(yesterdayLabel == "Yesterday")
    }
    
    if let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) {
      let label = viewModel.dayLabel(for: twoDaysAgo)
      let weekday = twoDaysAgo.formatted(.dateTime.weekday(.wide))
      #expect(label == "\(weekday) (D-2)")
    }
  }
  
  @Test("Visible day anchors are computed and clamped within time margins")
  func testVisibleDayAnchorsClamping() async throws {
    let now = simulatedNow.mutex.withLock { $0 }
    let calendar = Calendar.current
    let todayStart = calendar.startOfDay(for: now)
    
    // Viewport displaying a full 24h of 2 days ago
    guard let dayStart = calendar.date(byAdding: .day, value: -2, to: todayStart) else { return }
    let anchors = viewModel.computeVisibleDayAnchors(
      scrollPosition: dayStart,
      visibleDurationSeconds: 24 * 3600
    )
    
    // The anchor for 2 days ago should be present and centered at midday (12:00)
    if let anchor = anchors.first(where: { $0.label.contains("D-2") }) {
      let expectedMidday = dayStart.addingTimeInterval(12 * 3600)
      #expect(abs(anchor.date.timeIntervalSince(expectedMidday)) < 1.0)
    } else {
      #expect(Bool(false), "Expected anchor for D-2 to be computed")
    }
  }
  
  @Test("Debounced anchor updates update visibleDayAnchors deterministically")
  func testDebouncedAnchorUpdates() async throws {
    let now = simulatedNow.mutex.withLock { $0 }
    let calendar = Calendar.current
    let todayStart = calendar.startOfDay(for: now)
    
    viewModel.updateVisibleDayAnchorsDebounced(scrollPosition: todayStart, visibleDurationSeconds: 24 * 3600)
    
    // Advance virtual clock by debounce duration (50ms)
    await testClock.advance(by: .milliseconds(50))
    await viewModel.waitUntilIdle()
    
    #expect(!viewModel.visibleDayAnchors.isEmpty)
  }
}

