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

  func testPendingCAASDownload_persistenceRoundTrip() throws {
    let defaults = UserDefaults.standard
    let key = "pendingCAASDownload"
    let backupValue = defaults.object(forKey: key)

    defaults.removeObject(forKey: key)

    let service = PreferencesService()
    XCTAssertNil(service.pendingCAASDownload)

    let packageID = UUID()
    let createdAt = Date(timeIntervalSince1970: 1_737_900_000)
    let pending = PendingCAASDownload(
      packageID: packageID,
      layerID: "shom",
      layerName: "SHOM France",
      boundsWKT: "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
      zoomMax: 14,
      createdAt: createdAt
    )

    service.pendingCAASDownload = pending
    XCTAssertEqual(service.pendingCAASDownload, pending)

    // Reload from new instance
    let reloadedService = PreferencesService()
    XCTAssertEqual(reloadedService.pendingCAASDownload, pending)

    // Clear value
    service.pendingCAASDownload = nil
    XCTAssertNil(service.pendingCAASDownload)

    let clearedService = PreferencesService()
    XCTAssertNil(clearedService.pendingCAASDownload)

    if let backup = backupValue {
      defaults.set(backup, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }
}
