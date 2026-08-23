//
//  AppEnvironmentTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class AppEnvironmentTests: XCTestCase {

  private var environment: AppEnvironment!

  override func setUp() {
    super.setUp()
    environment = AppEnvironment()
    let prefs = PreferencesService()
    prefs.pendingCAASDownloads = []
    prefs.geoGarageCustomerID = nil
  }

  override func tearDown() {
    let prefs = PreferencesService()
    prefs.pendingCAASDownloads = []
    prefs.geoGarageCustomerID = nil
    environment = nil
    super.tearDown()
  }

  func testInitialStateIsUninitialized() {
    if case .uninitialized = environment.state {
      // Expected
    } else {
      XCTFail("Initial state should be uninitialized")
    }
    XCTAssertNil(environment.offlineSelectionViewModel)
  }

  func testBootstrapTransitionsToReadyAndExposesViewModels() async {
    await environment.bootstrap()

    if case .ready = environment.state {
      // Expected
    } else {
      XCTFail("State should be ready after bootstrap")
    }

    XCTAssertNotNil(environment.offlineSelectionViewModel)
    XCTAssertNotNil(environment.preferencesService)
    XCTAssertNotNil(environment.geoGarageDownloadRepository)
    XCTAssertNotNil(environment.geoGaragePackageService)
    XCTAssertNotNil(environment.geoGarageChartDownloader)
    XCTAssertNotNil(environment.geoGarageOfflineTileProvider)
  }

  func testBootstrap_triggersPendingDownloadRecoveryOnOfflineSelectionViewModel() async {
    let directPrefs = PreferencesService()
    directPrefs.geoGarageCustomerID = "cust_recovery_test"

    let pending = PendingCAASDownload(
      packageID: UUID(),
      layerID: "fr_shom",
      layerName: "France Atlantic",
      boundsWKT: "POLYGON((-5 48, -4 48, -4 49, -5 49, -5 48))",
      zoomMax: 14,
      createdAt: Date()
    )
    directPrefs.pendingCAASDownloads = [pending]

    await KeychainManager.shared.save(token: "test_access_token", for: "geogarage_access_token")

    addTeardownBlock {
      await MainActor.run {
        let cleanupPrefs = PreferencesService()
        cleanupPrefs.pendingCAASDownloads = []
        cleanupPrefs.geoGarageCustomerID = nil
      }
      await KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    }

    await environment.bootstrap()

    guard let offlineVM = environment.offlineSelectionViewModel else {
      XCTFail("offlineSelectionViewModel must be non-nil after bootstrap")
      return
    }

    for _ in 0..<100 {
      if offlineVM.isDownloading { break }
      try? await Task.sleep(for: .milliseconds(50))
    }

    XCTAssertTrue(offlineVM.isDownloading, "OfflineSelectionViewModel must be in downloading state after resume")
    XCTAssertNotEqual(offlineVM.downloadPhase, .idle, "Download phase must transition away from .idle upon resumption")
  }

  func testGlobalOfflineChartsDownloadStatus_initialState() {
    XCTAssertFalse(environment.isDownloadingOfflineCharts)
    XCTAssertNil(environment.offlineChartsDownloadProgress)
  }

  func testGlobalOfflineChartsDownloadStatus_whenOfflineMapManagerHasPendingDownloadsAndGeoGarageInactive() async {
    let pendingRegion = OfflineRegionInfo(
      id: "legacy_pack_1",
      name: "Legacy Chart",
      sizeInBytes: 1024,
      isComplete: false,
      progress: 0.4,
      expectedResources: 100,
      completedResources: 40,
      estimatedTimeRemaining: nil
    )
    environment.offlineMapManager.downloadedRegions = [pendingRegion]
    try? await Task.sleep(for: .milliseconds(50))

    // 1. Before bootstrap (geoGarageDownloadService is nil, offlineMapManager > 0)
    XCTAssertTrue(environment.isDownloadingOfflineCharts)
    XCTAssertEqual(environment.offlineChartsDownloadProgress, 0.4)

    // 2. After bootstrap (geoGarageDownloadService is present but isDownloading == false)
    await environment.bootstrap()
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(environment.geoGarageDownloadService?.isDownloading, false)
    XCTAssertTrue(environment.isDownloadingOfflineCharts, "isDownloadingOfflineCharts must return true when GeoGarage is inactive but offlineMapManager has pending downloads")
    XCTAssertEqual(environment.offlineChartsDownloadProgress, 0.4)
  }

  func testGlobalOfflineChartsDownloadStatus_whenNeitherIsDownloading() async {
    environment.offlineMapManager.downloadedRegions = []
    await environment.bootstrap()

    XCTAssertFalse(environment.isDownloadingOfflineCharts)
    XCTAssertNil(environment.offlineChartsDownloadProgress)
  }
}
