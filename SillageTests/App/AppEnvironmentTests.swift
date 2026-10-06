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
  /// Injected so the startup secret restore never reaches the real portal.
  private var partnerSecretService: MockGeoGaragePartnerSecretService!
  /// The `ChartViewModel` built by `bootstrap()` fetches the GeoGarage layers as soon as a token is
  /// in the Keychain: without a mocked session these tests would hit the real portal.
  private var authSession: URLSession!

  /// Mocked portal. 403 everywhere by default, like accounts.geogarage.com with an invalid Bearer;
  /// `tokenStatus`/`tokenBody` drive /o/token/. `MockURLProtocol` only serves the last handler set.
  private func installPortalHandler(tokenStatus: Int = 403, tokenBody: String = "") {
    MockURLProtocol.setHandler { request in
      let url = request.url ?? URL(fileURLWithPath: "/")
      let isTokenEndpoint = request.url?.path == "/o/token"  // URL.path drops the trailing "/"
      let status = isTokenEndpoint ? tokenStatus : 403
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) ?? HTTPURLResponse()
      return (response, isTokenEndpoint ? Data(tokenBody.utf8) : Data())
    }
  }

  override func setUp() async throws {
    try await super.setUp()
    MockURLProtocol.reset()
    installPortalHandler()
    authSession = MockURLProtocol.makeMockSession()
    partnerSecretService = MockGeoGaragePartnerSecretService()
    environment = AppEnvironment(partnerSecretService: partnerSecretService, authSession: authSession)
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
    MockURLProtocol.reset()
    environment = nil
    partnerSecretService = nil
    authSession = nil
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

  // MARK: - Package secret restored at startup

  func testBootstrapRestoresTheMissingPackageSecretForAnAlreadySignedInInstall() async {
    await KeychainManager.shared.save(token: "legacy_access_token", for: "geogarage_access_token")

    await environment.bootstrap()
    await environment.packageSecretRestoreTask?.value

    XCTAssertEqual(
      partnerSecretService.receivedAccessTokens,
      ["legacy_access_token"],
      "installation signed in before the secret endpoint existed: the secret must be fetched once at startup"
    )
  }

  /// The restore talks to the portal (15 s timeout, then possibly a refresh and a retry): on the
  /// critical path it could hold the launch screen up to 45 s at sea, connected without WAN.
  func testBootstrapReachesReadyBeforeTheSecretRestoreCompletes() async {
    await KeychainManager.shared.save(token: "legacy_access_token", for: "geogarage_access_token")

    await environment.bootstrap()

    guard case .ready = environment.state else {
      XCTFail("the app must be ready without waiting for the portal")
      return
    }
    let restoreTask = environment.packageSecretRestoreTask
    XCTAssertNotNil(restoreTask, "the restore must run in its own task, after the UI is shown")
    await restoreTask?.value
  }

  func testBootstrapDoesNotFetchThePackageSecretWhenTheKeychainAlreadyHasOne() async {
    await KeychainManager.shared.save(token: "legacy_access_token", for: "geogarage_access_token")
    await KeychainManager.shared.save(token: "already-here", for: GeoGaragePartnerSecretService.keychainAccount)

    await environment.bootstrap()
    await environment.packageSecretRestoreTask?.value

    XCTAssertTrue(partnerSecretService.receivedAccessTokens.isEmpty, "no network call when the secret is already there")
  }

  func testBootstrapWarnsWhenThePackageSecretCannotBeRestored() async {
    await KeychainManager.shared.save(token: "legacy_access_token", for: "geogarage_access_token")
    partnerSecretService.errorToThrow = .noProfile

    await environment.bootstrap()
    await environment.packageSecretRestoreTask?.value

    guard case .ready(let container) = environment.state else {
      XCTFail("bootstrap must succeed even without a secret")
      return
    }
    let warnings = container.messageService.messages.filter { $0.category == .offlineCharts && $0.severity == .warning }
    XCTAssertEqual(warnings.count, 1, "the user must know why the offline charts are gone")
  }

  func testBootstrapStaysSilentWhenThePackageSecretFetchIsOffline() async {
    await KeychainManager.shared.save(token: "legacy_access_token", for: "geogarage_access_token")
    partnerSecretService.errorToThrow = .networkError("offline")

    await environment.bootstrap()
    await environment.packageSecretRestoreTask?.value

    guard case .ready(let container) = environment.state else {
      XCTFail("bootstrap must succeed even without a secret")
      return
    }
    XCTAssertFalse(
      container.messageService.messages.contains { $0.category == .offlineCharts },
      "no coverage at launch: the next launch retries, no need to alarm"
    )
  }

  func testBootstrapRefreshesTokensWhenTheAccessTokenIsRejectedThenRetries() async {
    await KeychainManager.shared.save(token: "legacy_access_token", for: "geogarage_access_token")
    await KeychainManager.shared.save(token: "legacy_refresh_token", for: "geogarage_refresh_token")
    installPortalHandler(
      tokenStatus: 200,
      tokenBody: #"{"access_token":"refreshed-access","token_type":"Bearer","expires_in":86400,"refresh_token":"refreshed-refresh","scope":"write read"}"#
    )
    partnerSecretService.results = [.failure(.unauthorized), .success(partnerSecretService.secrets)]

    await environment.bootstrap()
    await environment.packageSecretRestoreTask?.value

    XCTAssertEqual(partnerSecretService.receivedAccessTokens.count, 2, "a single retry after the refresh")
    XCTAssertEqual(partnerSecretService.receivedAccessTokens.last, "refreshed-access", "the retry must carry the refreshed token")
    guard case .ready(let container) = environment.state else {
      XCTFail("bootstrap must succeed")
      return
    }
    XCTAssertFalse(
      container.messageService.messages.contains { $0.category == .offlineCharts },
      "the secret eventually arrived: no warning"
    )
  }

  /// Refresh token replaced or revoked: the Settings screen already shows "session expired". A
  /// "GeoGarage did not provide the secret" warning would be a second, misleading message.
  func testBootstrapStaysSilentWhenTheRefreshTokenIsDead() async throws {
    await KeychainManager.shared.save(token: "legacy_access_token", for: "geogarage_access_token")
    await KeychainManager.shared.save(token: "dead_refresh_token", for: "geogarage_refresh_token")
    installPortalHandler(tokenStatus: 400, tokenBody: #"{"error":"invalid_grant"}"#)
    partnerSecretService.results = [.failure(.unauthorized)]

    await environment.bootstrap()
    await environment.packageSecretRestoreTask?.value

    guard case .ready(let container) = environment.state else {
      XCTFail("bootstrap must succeed")
      return
    }
    XCTAssertFalse(
      container.messageService.messages.contains { $0.category == .offlineCharts },
      "the real cause is the expired session, not a missing secret"
    )
    let authError = try XCTUnwrap(container.geoGarageAuthService.authError as? AuthError)
    guard case .tokenExpired = authError else {
      XCTFail("the expired session must be published: \(authError)")
      return
    }
  }
}
