//
//  AppEnvironmentTestSupport.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import os
@testable import Sillage

/// Builds a hermetic baseline `AppEnvironment.Overrides` for unit tests so no real SQLite disk file,
/// MapLibre storage, CoreLocation manager, Keychain item, `UIApplication.shared`, or GeoGarage
/// network session is touched unless a test explicitly mutates a specific property on the returned struct.
@MainActor
func makeTestOverrides(userDefaults: UserDefaults) throws -> AppEnvironment.Overrides {
  var overrides = AppEnvironment.Overrides()
  overrides.configuration = AppConfiguration(geoGarageClientID: "test_client_id")
  overrides.offlineMapManager = OfflineMapManager(bindsToMapLibreStorage: false)
  overrides.partnerSecretService = MockGeoGaragePartnerSecretService()
  overrides.authSession = MockURLProtocol.makeMockSession()
  overrides.keychainManager = MockKeychainManager()
  overrides.userDefaults = userDefaults
  overrides.useDatabaseManager(try DatabaseManager.inMemory())
  overrides.useAnchorStateStore(MockAppEnvironmentAnchorStateStore())
  overrides.positioningService = MockPositioningService()
  overrides.chartDownloaderSessionConfiguration = MockURLProtocol.makeMockConfiguration()
  overrides.isProtectedDataAvailable = { true }
  return overrides
}

nonisolated final class MockAppEnvironmentAnchorStateStore: AnchorStateStoreProtocol, Sendable {
  private let sessionLock: OSAllocatedUnfairLock<AnchorSessionData>

  init(initialSession: AnchorSessionData = AnchorSessionData()) {
    self.sessionLock = OSAllocatedUnfairLock(initialState: initialSession)
  }

  func loadSession() -> AnchorSessionData {
    sessionLock.withLock { $0 }
  }

  func saveSession(_ session: AnchorSessionData) {
    sessionLock.withLock { $0 = session }
  }
}
