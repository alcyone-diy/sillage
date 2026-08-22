//
//  PreferencesServiceTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-07-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class PreferencesServiceTests: XCTestCase {

  func testBarometerAlarmIsDisabledByDefault() throws {
    // 1. Backup existing value
    let defaults = UserDefaults.standard
    let key = "isBaroAlarmEnabled"
    let backupValue = defaults.object(forKey: key)

    // 2. Clear the value to simulate a fresh install
    defaults.removeObject(forKey: key)

    // 3. Instantiate PreferencesService
    let service = PreferencesService()

    // 4. Verify default value is false
    XCTAssertFalse(service.isBaroAlarmEnabled, "Barometer alarm should be disabled by default")

    // 5. Restore the backup value
    if let backup = backupValue {
      defaults.set(backup, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  func testHUDEditOpenCount_DefaultsToZeroAndIncrementsCorrectly() throws {
    let defaults = UserDefaults.standard
    let key = "sillage.prefs.hudEditOpenCount"
    let backupValue = defaults.object(forKey: key)

    defaults.removeObject(forKey: key)

    let service = PreferencesService()
    XCTAssertEqual(service.hudEditOpenCount, 0)

    service.hudEditOpenCount += 1
    XCTAssertEqual(service.hudEditOpenCount, 1)

    let reloadedService = PreferencesService()
    XCTAssertEqual(reloadedService.hudEditOpenCount, 1)

    if let backup = backupValue {
      defaults.set(backup, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  func testPendingCAASDownloads_persistenceRoundTrip() throws {
    let defaults = UserDefaults.standard
    let key = "pendingCAASDownloads"
    let backupValue = defaults.object(forKey: key)

    defaults.removeObject(forKey: key)

    let service = PreferencesService()
    XCTAssertTrue(service.pendingCAASDownloads.isEmpty)

    let packageID1 = UUID()
    let packageID2 = UUID()
    let createdAt = Date(timeIntervalSince1970: 1_737_900_000)
    let pending1 = PendingCAASDownload(
      id: packageID1,
      packageID: packageID1,
      layerID: "shom",
      layerName: "SHOM France",
      boundsWKT: "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
      zoomMax: 14,
      createdAt: createdAt
    )
    let pending2 = PendingCAASDownload(
      id: packageID2,
      packageID: packageID2,
      layerID: "ukho",
      layerName: "UKHO Solent",
      boundsWKT: "POLYGON((-2 50, 0 50, 0 51, -2 51, -2 50))",
      zoomMax: 12,
      createdAt: createdAt
    )

    service.pendingCAASDownloads = [pending1, pending2]
    XCTAssertEqual(service.pendingCAASDownloads.count, 2)
    XCTAssertEqual(service.pendingCAASDownloads[0], pending1)
    XCTAssertEqual(service.pendingCAASDownloads[1], pending2)

    // Reload from new instance
    let reloadedService = PreferencesService()
    XCTAssertEqual(reloadedService.pendingCAASDownloads.count, 2)
    XCTAssertEqual(reloadedService.pendingCAASDownloads[0], pending1)
    XCTAssertEqual(reloadedService.pendingCAASDownloads[1], pending2)

    // Clear value
    service.pendingCAASDownloads = []
    XCTAssertTrue(service.pendingCAASDownloads.isEmpty)

    let clearedService = PreferencesService()
    XCTAssertTrue(clearedService.pendingCAASDownloads.isEmpty)

    if let backup = backupValue {
      defaults.set(backup, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  func testOneShotMigrationFromLegacyKey() throws {
    let defaults = UserDefaults.standard
    let legacyKey = "pendingCAASDownload"
    let newKey = "pendingCAASDownloads"

    let backupLegacy = defaults.object(forKey: legacyKey)
    let backupNew = defaults.object(forKey: newKey)

    defaults.removeObject(forKey: newKey)

    // Write a legacy single object to UserDefaults
    let legacyID = UUID()
    let legacyPending = PendingCAASDownload(
      id: legacyID,
      packageID: legacyID,
      layerID: "shom_legacy",
      layerName: "SHOM Legacy",
      boundsWKT: "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
      zoomMax: 14,
      createdAt: Date(timeIntervalSince1970: 1_737_900_000)
    )

    let legacyData = try JSONEncoder().encode(legacyPending)
    defaults.set(legacyData, forKey: legacyKey)

    // Initializing PreferencesService should perform the one-shot migration
    let service = PreferencesService()

    XCTAssertEqual(service.pendingCAASDownloads.count, 1)
    XCTAssertEqual(service.pendingCAASDownloads.first?.id, legacyID)
    XCTAssertEqual(service.pendingCAASDownloads.first?.layerName, "SHOM Legacy")

    // The legacy key must be removed immediately
    XCTAssertNil(defaults.data(forKey: legacyKey), "Legacy pendingCAASDownload key must be deleted after one-shot migration")

    // The new key must now contain the data
    XCTAssertNotNil(defaults.data(forKey: newKey), "New pendingCAASDownloads key must be set after migration")

    // Cleanup
    defaults.removeObject(forKey: legacyKey)
    defaults.removeObject(forKey: newKey)
    if let backupLegacy { defaults.set(backupLegacy, forKey: legacyKey) }
    if let backupNew { defaults.set(backupNew, forKey: newKey) }
  }
}
