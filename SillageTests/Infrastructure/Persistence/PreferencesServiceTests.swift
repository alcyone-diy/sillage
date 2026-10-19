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

  private var isolatedDefaults: IsolatedUserDefaults?

  override func setUp() {
    super.setUp()
    isolatedDefaults = IsolatedUserDefaults(prefix: "PreferencesServiceTests")
  }

  override func tearDown() {
    isolatedDefaults?.tearDown()
    isolatedDefaults = nil
    super.tearDown()
  }

  func testBarometerAlarmIsDisabledByDefault() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let service = PreferencesService(defaults: defaults)

    XCTAssertFalse(service.isBaroAlarmEnabled, "Barometer alarm should be disabled by default")
  }

  func testHUDEditOpenCount_DefaultsToZeroAndIncrementsCorrectly() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let service = PreferencesService(defaults: defaults)
    XCTAssertEqual(service.hudEditOpenCount, 0)

    service.hudEditOpenCount += 1
    XCTAssertEqual(service.hudEditOpenCount, 1)

    let reloadedService = PreferencesService(defaults: defaults)
    XCTAssertEqual(reloadedService.hudEditOpenCount, 1)
  }

  func testPendingCAASDownloads_persistenceRoundTrip() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let service = PreferencesService(defaults: defaults)
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
      createdAt: createdAt,
      replacesChartID: UUID()
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
    let reloadedService = PreferencesService(defaults: defaults)
    XCTAssertEqual(reloadedService.pendingCAASDownloads.count, 2)
    XCTAssertEqual(reloadedService.pendingCAASDownloads[0], pending1)
    XCTAssertEqual(reloadedService.pendingCAASDownloads[1], pending2)

    // Clear value
    service.pendingCAASDownloads = []
    XCTAssertTrue(service.pendingCAASDownloads.isEmpty)

    let clearedService = PreferencesService(defaults: defaults)
    XCTAssertTrue(clearedService.pendingCAASDownloads.isEmpty)
  }

  func testPendingCAASDownload_updatingPackageID() {
    let initial = PendingCAASDownload(
      id: UUID(),
      packageID: nil,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
      zoomMax: 14,
      customName: "My Chart",
      replacesChartID: UUID()
    )
    let newPackageID = UUID()
    let updated = initial.updating(packageID: newPackageID)

    XCTAssertEqual(updated.id, initial.id)
    XCTAssertEqual(updated.packageID, newPackageID)
    XCTAssertEqual(updated.layerID, initial.layerID)
    XCTAssertEqual(updated.layerName, initial.layerName)
    XCTAssertEqual(updated.boundsWKT, initial.boundsWKT)
    XCTAssertEqual(updated.zoomMax, initial.zoomMax)
    XCTAssertEqual(updated.createdAt, initial.createdAt)
    XCTAssertEqual(updated.customName, initial.customName)
    XCTAssertEqual(updated.replacesChartID, initial.replacesChartID)
  }

  func testPendingCAASDownload_updatingReplacesChartID() {
    let initialReplacesID = UUID()
    let initial = PendingCAASDownload(
      id: UUID(),
      packageID: UUID(),
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
      zoomMax: 14,
      customName: "My Chart",
      replacesChartID: initialReplacesID
    )

    let updatedCleared = initial.updating(replacesChartID: nil)
    XCTAssertEqual(updatedCleared.id, initial.id)
    XCTAssertEqual(updatedCleared.packageID, initial.packageID)
    XCTAssertNil(updatedCleared.replacesChartID)

    let newReplacesID = UUID()
    let updatedNew = updatedCleared.updating(replacesChartID: newReplacesID)
    XCTAssertEqual(updatedNew.replacesChartID, newReplacesID)
  }

  func testClearAll_ResetsAllPreferencesToDefaults() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let service = PreferencesService(defaults: defaults)

    service.savedChartSource = "customSource"
    service.savedGeoGarageLayerID = "customLayer"
    service.saveCameraState(coordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0), zoom: 12.0, direction: 90.0)
    service.savedTrackingMode = .courseUp
    service.gloveModeEnabled = true
    service.hasAcceptedDisclaimer = true
    service.isOpenSeaMapOverlayEnabled = true
    service.geoGarageCustomerID = "cust123"
    service.hudEditOpenCount = 5
    service.isBaroAlarmEnabled = true
    service.barometerOffset = Measurement(value: 2.5, unit: .hectopascals)
    service.pendingCAASDownloads = [
      PendingCAASDownload(layerID: "test", layerName: "Test", boundsWKT: "POLYGON(())", zoomMax: 10)
    ]

    service.clearAll()

    XCTAssertNil(service.savedChartSource)
    XCTAssertNil(service.savedGeoGarageLayerID)
    XCTAssertNil(service.loadCameraState())
    XCTAssertNil(service.savedTrackingMode)
    XCTAssertFalse(service.gloveModeEnabled)
    XCTAssertFalse(service.hasAcceptedDisclaimer)
    XCTAssertFalse(service.isOpenSeaMapOverlayEnabled)
    XCTAssertNil(service.geoGarageCustomerID)
    XCTAssertEqual(service.hudEditOpenCount, 0)
    XCTAssertFalse(service.isBaroAlarmEnabled)
    XCTAssertEqual(service.barometerOffset.value, 0.0)
    XCTAssertTrue(service.pendingCAASDownloads.isEmpty)

    let reloaded = PreferencesService(defaults: defaults)
    XCTAssertNil(reloaded.savedChartSource)
    XCTAssertNil(reloaded.savedGeoGarageLayerID)
    XCTAssertNil(reloaded.loadCameraState())
    XCTAssertNil(reloaded.savedTrackingMode)
    XCTAssertFalse(reloaded.gloveModeEnabled)
    XCTAssertFalse(reloaded.hasAcceptedDisclaimer)
    XCTAssertFalse(reloaded.isOpenSeaMapOverlayEnabled)
    XCTAssertNil(reloaded.geoGarageCustomerID)
    XCTAssertEqual(reloaded.hudEditOpenCount, 0)
    XCTAssertFalse(reloaded.isBaroAlarmEnabled)
    XCTAssertEqual(reloaded.barometerOffset.value, 0.0)
    XCTAssertTrue(reloaded.pendingCAASDownloads.isEmpty)
  }

  func testCustomerIDRestoredFromKeychainWhenUserDefaultsIsWiped() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let mockKeychain = MockKeychainManager()
    mockKeychain.saveSync(token: "cus_reinstall", for: GeoGarageKeychainKeys.customerID)

    let service = PreferencesService(defaults: defaults, keychainManager: mockKeychain)

    XCTAssertEqual(service.geoGarageCustomerID, "cus_reinstall", "CustomerID should be restored from Keychain after reinstall")
    XCTAssertEqual(defaults.string(forKey: "geogarage_customer_id"), "cus_reinstall", "CustomerID restored from Keychain should be resynced to defaults")
  }

  func testCustomerIDSettingSyncsToKeychainAndClearingDeletesFromKeychain() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let mockKeychain = MockKeychainManager()
    let service = PreferencesService(defaults: defaults, keychainManager: mockKeychain)

    service.geoGarageCustomerID = "cus_sync_test"
    XCTAssertEqual(mockKeychain.retrieveTokenSync(for: GeoGarageKeychainKeys.customerID), "cus_sync_test")
    XCTAssertEqual(defaults.string(forKey: "geogarage_customer_id"), "cus_sync_test")

    service.geoGarageCustomerID = nil
    XCTAssertNil(mockKeychain.retrieveTokenSync(for: GeoGarageKeychainKeys.customerID))
    XCTAssertNil(defaults.string(forKey: "geogarage_customer_id"))
  }

  func testCustomerIDMigratedFromUserDefaultsToKeychainOnAppUpdate() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let mockKeychain = MockKeychainManager()
    // User already had customerID in UserDefaults from previous version, Keychain empty
    defaults.set("cus_existing_user", forKey: "geogarage_customer_id")
    XCTAssertNil(mockKeychain.retrieveTokenSync(for: GeoGarageKeychainKeys.customerID))

    let service = PreferencesService(defaults: defaults, keychainManager: mockKeychain)

    XCTAssertEqual(service.geoGarageCustomerID, "cus_existing_user")
    XCTAssertEqual(
      mockKeychain.retrieveTokenSync(for: GeoGarageKeychainKeys.customerID),
      "cus_existing_user",
      "CustomerID should be migrated to Keychain on first launch after update"
    )
  }
}
