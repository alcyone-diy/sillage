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
@testable import Sillage

@MainActor
@Suite("Barometer View Model Tests")
final class BarometerViewModelTests {
  let dbManager: DatabaseManager
  let store: BarometricHistoryStore
  let preferencesService: PreferencesService
  let notificationService: LocalNotificationService
  let permissionService: PermissionService
  let positioningService: CoreLocationPositioningService
  let barometricService: BarometricService
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
    viewModel = BarometerViewModel(
      service: barometricService,
      preferencesService: preferencesService
    )
  }
  
  @Test("Debounced refresh cancels preceding rapid requests")
  func testDebouncedRefreshCancelsPrecedingRequests() async throws {
    let now = Date.now
    
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
    
    // Wait for the 150ms debounce sleep to settle
    try await Task.sleep(for: .milliseconds(250))
    
    // Only the second request (intervalRecent with r1) should have been loaded
    #expect(viewModel.history24h.count == 1)
    #expect(viewModel.history24h.first?.pressure.value == 1010.0)
  }
}
