//
//  AppEnvironment+Overrides.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

extension AppEnvironment {
  /// Optional dependency and lifecycle overrides for tests, SwiftUI previews, and debug scenarios.
  /// Production leaves all properties `nil` via `AppEnvironment()`.
  @MainActor
  struct Overrides {
    var metadata: AppMetadata? = nil
    var configuration: AppConfiguration? = nil
    var offlineMapManager: OfflineMapManager? = nil
    var partnerSecretService: (any GeoGaragePartnerSecretServiceProtocol)? = nil
    var authSession: URLSession? = nil
    var keychainManager: (any KeychainManaging)? = nil
    var tileProxyManager: (any TileProxyManagerProtocol)? = nil
    var preferencesService: PreferencesService? = nil
    var userDefaults: UserDefaults? = nil
    var databaseManagerFactory: (@Sendable () throws -> DatabaseManager)? = nil
    var anchorStateStoreLoader: (@Sendable () async -> any AnchorStateStoreProtocol)? = nil
    var positioningService: (any PositioningService)? = nil
    var chartDownloaderSessionConfiguration: URLSessionConfiguration? = nil
    var isProtectedDataAvailable: (@MainActor () -> Bool)? = nil

    #if DEBUG
    var screenshotScenario: ScreenshotScenario? = nil
    #endif

    /// Wraps a pre-created `Sendable` `DatabaseManager` (e.g. `.inMemory()`) into `databaseManagerFactory`.
    mutating func useDatabaseManager(_ manager: DatabaseManager) {
      databaseManagerFactory = { manager }
    }

    /// Wraps a pre-created `Sendable` `AnchorStateStoreProtocol` into `anchorStateStoreLoader`.
    mutating func useAnchorStateStore(_ store: any AnchorStateStoreProtocol) {
      anchorStateStoreLoader = { store }
    }
  }
}
