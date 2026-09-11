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
  /// Injecté pour que le rattrapage du secret au démarrage n'appelle jamais le vrai portail
  /// (revue de la Task 5, 11 sept. 2026).
  private var partnerSecretService: MockGeoGaragePartnerSecretService!

  override func setUp() async throws {
    try await super.setUp()
    partnerSecretService = MockGeoGaragePartnerSecretService()
    environment = AppEnvironment(partnerSecretService: partnerSecretService)
    let prefs = PreferencesService()
    prefs.pendingCAASDownloads = []
    prefs.geoGarageCustomerID = nil
    await KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    await KeychainManager.shared.deleteToken(for: "geogarage_refresh_token")
    await KeychainManager.shared.deleteToken(for: GeoGaragePartnerSecretService.keychainAccount)
  }

  override func tearDown() async throws {
    let prefs = PreferencesService()
    prefs.pendingCAASDownloads = []
    prefs.geoGarageCustomerID = nil
    await KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    await KeychainManager.shared.deleteToken(for: "geogarage_refresh_token")
    await KeychainManager.shared.deleteToken(for: GeoGaragePartnerSecretService.keychainAccount)
    environment = nil
    partnerSecretService = nil
    try await super.tearDown()
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

  // MARK: - Secret de paquets rattrapé au démarrage (revue de la Task 5, 11 sept. 2026)

  func testBootstrapRestoresTheMissingPackageSecretForAnAlreadySignedInInstall() async {
    await KeychainManager.shared.save(token: "legacy_access_token", for: "geogarage_access_token")

    await environment.bootstrap()

    XCTAssertEqual(
      partnerSecretService.receivedAccessTokens,
      ["legacy_access_token"],
      "installation connectée avant la voie B : le secret doit être demandé une fois au démarrage"
    )
  }

  func testBootstrapDoesNotFetchThePackageSecretWhenTheKeychainAlreadyHasOne() async {
    await KeychainManager.shared.save(token: "legacy_access_token", for: "geogarage_access_token")
    await KeychainManager.shared.save(token: "already-here", for: GeoGaragePartnerSecretService.keychainAccount)

    await environment.bootstrap()

    XCTAssertTrue(partnerSecretService.receivedAccessTokens.isEmpty, "aucun appel réseau si le secret est déjà là")
  }

  func testBootstrapWarnsWhenThePackageSecretCannotBeRestored() async {
    await KeychainManager.shared.save(token: "legacy_access_token", for: "geogarage_access_token")
    partnerSecretService.errorToThrow = .noProfile

    await environment.bootstrap()

    guard case .ready(let container) = environment.state else {
      XCTFail("bootstrap doit aboutir même sans secret")
      return
    }
    let warnings = container.messageService.messages.filter { $0.category == .geoGarage && $0.severity == .warning }
    XCTAssertEqual(warnings.count, 1, "l'utilisateur doit savoir pourquoi ses cartes hors ligne ont disparu")
  }

  func testBootstrapStaysSilentWhenThePackageSecretFetchIsOffline() async {
    await KeychainManager.shared.save(token: "legacy_access_token", for: "geogarage_access_token")
    partnerSecretService.errorToThrow = .networkError("offline")

    await environment.bootstrap()

    guard case .ready(let container) = environment.state else {
      XCTFail("bootstrap doit aboutir même sans secret")
      return
    }
    XCTAssertFalse(
      container.messageService.messages.contains { $0.category == .geoGarage && $0.severity == .warning },
      "hors couverture au lancement : la prochaine ouverture réessaiera, inutile d'alarmer"
    )
  }
}
