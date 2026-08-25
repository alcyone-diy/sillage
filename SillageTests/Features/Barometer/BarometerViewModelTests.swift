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
@Suite(.serialized, "Barometer View Model Tests")
final class BarometerViewModelTests {
  let dbManager: DatabaseManager
  let store: BarometricHistoryStore
  let preferencesService: PreferencesService
  let notificationService: LocalNotificationService
  let permissionService: PermissionService
  let positioningService: CoreLocationPositioningService
  let barometricService: BarometricService
  let testClock: TestClock<Duration>
  let simulatedNow: Mutex<Date>
  let viewModel: BarometerViewModel
  
  init() throws {
    dbManager = try DatabaseManager.inMemory()
    store = BarometricHistoryStore(databaseManager: dbManager)
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
      permissionService: permissionService
    )
    let clock = TestClock()
    let nowMutex = Mutex(Date(timeIntervalSince1970: 1_700_000_000))
    self.testClock = clock
    self.simulatedNow = nowMutex
    self.viewModel = BarometerViewModel(
      service: barometricService,
      preferencesService: preferencesService,
      clock: clock,
      dateProvider: { nowMutex.withLock { $0 } }
    )
  }
  
  @Test("Debounced refresh cancels preceding rapid requests")
  func testDebouncedRefreshCancelsPrecedingRequests() async throws {
    let now = simulatedNow.withLock { $0 }
    
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
    
    // Allow the debounced task to start and suspend on clock.sleep
    for _ in 0..<10 { await Task.yield() }
    
    // Virtual advance through test clock (instantaneous, no real-time wait!)
    await testClock.advance(by: .milliseconds(150))
    
    // Allow the resumed task to fetch and process readings
    for _ in 0..<10 { await Task.yield() }
    
    // Only the second request (intervalRecent with r1) should have been loaded
    #expect(viewModel.history24h.count == 1)
    #expect(viewModel.history24h.first?.pressure.value == 1010.0)
  }
  
  @Test("Latest timestamp remains anchored to current time when querying past history")
  func testLatestTimestampRemainsAnchoredToPresentWhenLoadingPastHistory() async throws {
    let now = simulatedNow.withLock { $0 }
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
    let before = simulatedNow.withLock { $0 }
    #expect(viewModel.latestTimestamp == before)
    
    let advancedDate = before.addingTimeInterval(3600)
    simulatedNow.withLock { $0 = advancedDate }
    viewModel.updateLatestTimestamp()
    
    #expect(viewModel.latestTimestamp == advancedDate)
  }
}

