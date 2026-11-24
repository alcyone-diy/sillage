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
import CoreLocation
import os
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

  private var mockKeychain: MockKeychainManager!
  private var isolatedDefaults: IsolatedUserDefaults!
  private var testPreferencesService: PreferencesService!
  private var testDatabaseManager: DatabaseManager!

  override func setUp() async throws {
    try await super.setUp()
    TileProxyProtocol.resetForTesting()
    MockURLProtocol.reset()
    installPortalHandler()
    authSession = MockURLProtocol.makeMockSession()
    partnerSecretService = MockGeoGaragePartnerSecretService()
    mockKeychain = MockKeychainManager()
    isolatedDefaults = IsolatedUserDefaults(prefix: "AppEnvironmentTests")
    testPreferencesService = PreferencesService(defaults: isolatedDefaults.defaults, keychainManager: mockKeychain)
    testPreferencesService.clearAll()
    testDatabaseManager = try DatabaseManager.inMemory()
    environment = AppEnvironment(
      configuration: AppConfiguration(geoGarageClientID: "test_client_id"),
      offlineMapManager: OfflineMapManager(bindsToMapLibreStorage: false),
      partnerSecretService: partnerSecretService,
      authSession: authSession,
      keychainManager: mockKeychain,
      preferencesService: testPreferencesService,
      userDefaults: isolatedDefaults.defaults,
      databaseManager: testDatabaseManager,
      anchorStateStore: MockAppEnvironmentAnchorStateStore(),
      positioningService: MockPositioningService(),
      chartDownloaderSessionConfiguration: MockURLProtocol.makeMockConfiguration()
    )
  }

  override func tearDown() async throws {
    testDatabaseManager = nil
    testPreferencesService?.clearAll()
    isolatedDefaults?.tearDown()
    isolatedDefaults = nil
    testPreferencesService = nil
    mockKeychain = nil
    MockURLProtocol.reset()
    TileProxyProtocol.resetForTesting()
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

  func testBootstrapTransitionsToReadyAndExposesViewModels() async throws {
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
    XCTAssertNotNil(environment.geoGarageLayerRepository)
  }

  func testBootstrap_executesLifecycleWithInMemoryDatabaseWithoutResidualCachesFile() async throws {
    let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    let legacyCacheFile = cachesDir?.appendingPathComponent("geogarage_layers.json")

    if let path = legacyCacheFile?.path, FileManager.default.fileExists(atPath: path) {
      try? FileManager.default.removeItem(atPath: path)
    }

    await environment.bootstrap()

    if case .ready = environment.state {
      // Expected
    } else {
      XCTFail("State should be ready after bootstrap")
    }

    XCTAssertNotNil(environment.geoGarageLayerRepository)

    if let path = legacyCacheFile?.path {
      XCTAssertFalse(FileManager.default.fileExists(atPath: path), "No geogarage_layers.json file should be written to Library/Caches during bootstrap.")
    }
  }

  func testBootstrap_triggersPendingDownloadRecoveryOnOfflineSelectionViewModel() async throws {
    let packageID = UUID()
    testPreferencesService.geoGarageCustomerID = "cust_recovery_test"

    let pending = PendingCAASDownload(
      packageID: packageID,
      layerID: "fr_shom",
      layerName: "France Atlantic",
      boundsWKT: "POLYGON((-5 48, -4 48, -4 49, -5 49, -5 48))",
      zoomMax: 14,
      createdAt: Date()
    )
    testPreferencesService.pendingCAASDownloads = [pending]

    try await mockKeychain.save(token: "test_access_token", for: GeoGarageKeychainKeys.accessToken)
    try await mockKeychain.save(token: "cust_recovery_test", for: GeoGarageKeychainKeys.customerID)

    let expectedPackagePath = "/packages/\(packageID.uuidString.lowercased())"
    MockURLProtocol.setHandler { request in
      guard let url = request.url else {
        XCTFail("Expected request URL in MockURLProtocol handler")
        return (HTTPURLResponse(), Data())
      }
      if request.httpMethod == "GET" && url.path == expectedPackagePath {
        let body = #"{"uuid":"\#(packageID.uuidString.lowercased())","state":"PROGRESS","monitor":"10/100"}"#
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
          XCTFail("Failed to construct HTTPURLResponse(200) for \(url)")
          return (HTTPURLResponse(), Data())
        }
        return (response, Data(body.utf8))
      }
      guard let response = HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil) else {
        XCTFail("Failed to construct HTTPURLResponse(403) for \(url)")
        return (HTTPURLResponse(), Data())
      }
      return (response, Data())
    }

    let keychain = mockKeychain
    let env = environment
    addTeardownBlock { @MainActor in
      env?.geoGarageDownloadService?.cancelDownload()
      try? await keychain?.deleteToken(for: GeoGarageKeychainKeys.accessToken)
      try? await keychain?.deleteToken(for: GeoGarageKeychainKeys.customerID)
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

  func testGlobalOfflineChartsDownloadStatus_whenOfflineMapManagerHasPendingDownloadsAndGeoGarageInactive() async throws {
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

  func testGlobalOfflineChartsDownloadStatus_whenNeitherIsDownloading() async throws {
    environment.offlineMapManager.downloadedRegions = []
    await environment.bootstrap()

    XCTAssertFalse(environment.isDownloadingOfflineCharts)
    XCTAssertNil(environment.offlineChartsDownloadProgress)
  }

  // MARK: - Package secret restored at startup

  func testBootstrapRestoresTheMissingPackageSecretForAnAlreadySignedInInstall() async throws {
    try await mockKeychain.save(token: "legacy_access_token", for: GeoGarageKeychainKeys.accessToken)

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
  func testBootstrapReachesReadyBeforeTheSecretRestoreCompletes() async throws {
    try await mockKeychain.save(token: "legacy_access_token", for: GeoGarageKeychainKeys.accessToken)

    await environment.bootstrap()

    guard case .ready = environment.state else {
      XCTFail("the app must be ready without waiting for the portal")
      return
    }
    let restoreTask = environment.packageSecretRestoreTask
    XCTAssertNotNil(restoreTask, "the restore must run in its own task, after the UI is shown")
    await restoreTask?.value
  }

  func testBootstrapDoesNotFetchThePackageSecretWhenTheKeychainAlreadyHasOne() async throws {
    try await mockKeychain.save(token: "legacy_access_token", for: GeoGarageKeychainKeys.accessToken)
    try await mockKeychain.save(token: "already-here", for: GeoGaragePartnerSecretService.keychainAccount)
    try await mockKeychain.save(token: "cus_already_here", for: GeoGarageKeychainKeys.customerID)

    await environment.bootstrap()
    await environment.packageSecretRestoreTask?.value

    XCTAssertTrue(partnerSecretService.receivedAccessTokens.isEmpty, "no network call when both secret and customerID are already there")
  }

  func testBootstrapFetchesCredentialsWhenCustomerIDIsMissingEvenIfSecretIsPresent() async throws {
    try await mockKeychain.save(token: "legacy_access_token", for: GeoGarageKeychainKeys.accessToken)
    try await mockKeychain.save(token: "already-here", for: GeoGaragePartnerSecretService.keychainAccount)
    // customerID is missing in Keychain and Defaults (e.g. app reinstalled after older version)
    partnerSecretService.secrets = GeoGaragePartnerSecrets(
      clientID: "mock-client",
      customerID: "cus_restored_from_portal",
      packageSecret: "already-here",
      teaSecret: ""
    )

    await environment.bootstrap()
    await environment.packageSecretRestoreTask?.value

    XCTAssertEqual(
      partnerSecretService.receivedAccessTokens,
      ["legacy_access_token"],
      "must fetch credentials when customerID is missing even if secret is in Keychain"
    )
    XCTAssertEqual(testPreferencesService.geoGarageCustomerID, "cus_restored_from_portal")
  }

  func testBootstrapWarnsWhenThePackageSecretCannotBeRestored() async throws {
    try await mockKeychain.save(token: "legacy_access_token", for: GeoGarageKeychainKeys.accessToken)
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

  func testBootstrapStaysSilentWhenThePackageSecretFetchIsOffline() async throws {
    try await mockKeychain.save(token: "legacy_access_token", for: GeoGarageKeychainKeys.accessToken)
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

  func testBootstrapRefreshesTokensWhenTheAccessTokenIsRejectedThenRetries() async throws {
    try await mockKeychain.save(token: "legacy_access_token", for: GeoGarageKeychainKeys.accessToken)
    try await mockKeychain.save(token: "legacy_refresh_token", for: GeoGarageKeychainKeys.refreshToken)
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
    try await mockKeychain.save(token: "legacy_access_token", for: GeoGarageKeychainKeys.accessToken)
    try await mockKeychain.save(token: "dead_refresh_token", for: GeoGarageKeychainKeys.refreshToken)
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

  func testBootstrap_restoresInjectedArmedAnchorSessionOnReady() async throws {
    let watch = AnchorWatch(
      coordinate: CLLocationCoordinate2D(latitude: 47.2, longitude: -1.5),
      radius: Measurement(value: 45, unit: .meters),
      initialAccuracy: Measurement(value: 6, unit: .meters)
    )
    let mockStore = MockAppEnvironmentAnchorStateStore(
      initialSession: AnchorSessionData(activeWatch: watch, status: .armed, triggerReason: nil)
    )
    // Inject a mock PositioningService so simulated CoreLocation fixes far from (47.2, -1.5)
    // do not immediately transition the restored watch from `.armed` to `.dragging`.
    let restoredEnv = AppEnvironment(
      offlineMapManager: OfflineMapManager(bindsToMapLibreStorage: false),
      partnerSecretService: partnerSecretService,
      authSession: authSession,
      keychainManager: mockKeychain,
      preferencesService: testPreferencesService,
      userDefaults: isolatedDefaults.defaults,
      databaseManager: testDatabaseManager,
      anchorStateStore: mockStore,
      positioningService: MockPositioningService(),
      chartDownloaderSessionConfiguration: MockURLProtocol.makeMockConfiguration()
    )

    await restoredEnv.bootstrap()

    guard case .ready(let container) = restoredEnv.state else {
      XCTFail("AppEnvironment must transition to .ready after bootstrap")
      return
    }
    XCTAssertEqual(container.anchorService.status, .armed)
    XCTAssertEqual(container.anchorService.activeWatch?.radius, Measurement(value: 45, unit: .meters))
    XCTAssertEqual(container.anchorViewModel.status, .armed)
    XCTAssertEqual(container.anchorViewModel.configuredRadius, Measurement(value: 45, unit: .meters))

    // Clean up background GPS task started on armed restoration
    container.anchorService.clear()
    XCTAssertEqual(mockStore.loadSession().status, .inactive)
  }

  func testAppConfiguration_normalizesEmptyQuotesAndPlaceholdersToNil() {
    XCTAssertNil(AppConfiguration(geoGarageClientID: nil).geoGarageClientID)
    XCTAssertFalse(AppConfiguration(geoGarageClientID: nil).isGeoGarageConfigured)

    XCTAssertNil(AppConfiguration(geoGarageClientID: "").geoGarageClientID)
    XCTAssertNil(AppConfiguration(geoGarageClientID: "   \n  ").geoGarageClientID)
    XCTAssertNil(AppConfiguration(geoGarageClientID: " \"\" ").geoGarageClientID)
    XCTAssertNil(AppConfiguration(geoGarageClientID: "\"   \"").geoGarageClientID)
    XCTAssertNil(AppConfiguration(geoGarageClientID: "$(GEOGARAGE_CLIENT_ID)").geoGarageClientID)

    let valid = AppConfiguration(geoGarageClientID: " \"my-client-id\" ")
    XCTAssertEqual(valid.geoGarageClientID, "my-client-id")
    XCTAssertTrue(valid.isGeoGarageConfigured)
  }

  // MARK: - OfflineMapManager Pure Init & Idempotent Start

  func testOfflineMapManager_isNotStartedOnInit_andStartsIdempotentlyDuringBootstrap() async {
    XCTAssertFalse(environment.offlineMapManager.isStarted, "OfflineMapManager must remain unstarted in pure AppEnvironment.init()")

    await environment.bootstrap()
    XCTAssertTrue(environment.offlineMapManager.isStarted, "OfflineMapManager must start during bootstrap()")

    // Calling start() a second time must be a safe no-op
    environment.offlineMapManager.start()
    XCTAssertTrue(environment.offlineMapManager.isStarted)
  }

  // MARK: - Background URLSession Completion Routing Across Lifecycle Windows

  func testBackgroundSessionCompletion_registeredBeforeBootstrap_isInjectedIntoDownloaderOnInit() async throws {
    let invoked = expectation(description: "Background completion handler invoked via downloader init injection")
    var callCount = 0

    environment.registerBackgroundURLSessionCompletionHandler {
      callCount += 1
      invoked.fulfill()
    }

    await environment.bootstrap()
    let downloader = try XCTUnwrap(environment.geoGarageChartDownloader)
    downloader.urlSessionDidFinishEvents(forBackgroundURLSession: authSession)

    await fulfillment(of: [invoked], timeout: 2.0)
    XCTAssertEqual(callCount, 1)
  }

  func testBackgroundSessionCompletion_registeredBetweenDownloaderInitAndReady_isForwardedImmediately() async throws {
    let (enteredWindowBStream, enteredWindowBContinuation) = AsyncStream<Void>.makeStream()
    let (releaseBootstrapStream, releaseBootstrapContinuation) = AsyncStream<Void>.makeStream()

    environment.anchorStateStoreLoaderOverride = {
      enteredWindowBContinuation.yield()
      enteredWindowBContinuation.finish()
      var releaseIterator = releaseBootstrapStream.makeAsyncIterator()
      _ = await releaseIterator.next()
      return MockAppEnvironmentAnchorStateStore()
    }

    let bootstrapTask = Task { @MainActor in
      await self.environment.bootstrap()
    }
    defer {
      // Idempotent safety net: guarantees `anchorStateStoreLoaderOverride` is never left suspended
      // even if an assertion or `XCTUnwrap` throws before the end of the test.
      releaseBootstrapContinuation.finish()
    }

    var enteredIterator = enteredWindowBStream.makeAsyncIterator()
    _ = await enteredIterator.next()

    XCTAssertNotNil(environment.activeChartDownloader, "Downloader must be instantiated before registering Window B handler")
    guard case .bootstrapping = environment.state else {
      XCTFail("Expected environment to still be in .bootstrapping inside Window B")
      releaseBootstrapContinuation.finish()
      await bootstrapTask.value
      return
    }

    let invoked = expectation(description: "Background completion handler invoked during bootstrapping window")
    var callCount = 0
    environment.registerBackgroundURLSessionCompletionHandler {
      callCount += 1
      invoked.fulfill()
    }

    releaseBootstrapContinuation.finish()
    await bootstrapTask.value

    let downloader = try XCTUnwrap(environment.geoGarageChartDownloader)
    downloader.urlSessionDidFinishEvents(forBackgroundURLSession: authSession)

    await fulfillment(of: [invoked], timeout: 2.0)
    XCTAssertEqual(callCount, 1)
  }

  func testBackgroundSessionCompletion_registeredAfterReady_isForwardedDirectlyToDownloader() async throws {
    await environment.bootstrap()
    let downloader = try XCTUnwrap(environment.geoGarageChartDownloader)

    let invoked = expectation(description: "Background completion handler invoked when registered in .ready state")
    var callCount = 0
    environment.registerBackgroundURLSessionCompletionHandler {
      callCount += 1
      invoked.fulfill()
    }

    downloader.urlSessionDidFinishEvents(forBackgroundURLSession: authSession)
    await fulfillment(of: [invoked], timeout: 2.0)
    XCTAssertEqual(callCount, 1)
  }

  func testBackgroundSessionCompletion_whenBootstrapFails_invokesAndDrainsPendingHandler() async {
    struct SimulatedBootstrapFailure: LocalizedError {
      var errorDescription: String? { "Simulated database failure" }
    }

    let failingEnv = AppEnvironment(
      configuration: AppConfiguration(geoGarageClientID: "test_client_id"),
      offlineMapManager: OfflineMapManager(bindsToMapLibreStorage: false),
      partnerSecretService: partnerSecretService,
      authSession: authSession,
      keychainManager: mockKeychain,
      preferencesService: testPreferencesService,
      userDefaults: isolatedDefaults.defaults,
      databaseManager: nil,
      anchorStateStore: MockAppEnvironmentAnchorStateStore(),
      positioningService: MockPositioningService(),
      chartDownloaderSessionConfiguration: MockURLProtocol.makeMockConfiguration()
    )
    failingEnv.databaseManagerFactoryOverride = { throw SimulatedBootstrapFailure() }

    var callCount = 0
    failingEnv.registerBackgroundURLSessionCompletionHandler {
      callCount += 1
    }

    await failingEnv.bootstrap()

    guard case .error = failingEnv.state else {
      XCTFail("Expected .error state when databaseManagerFactoryOverride throws")
      return
    }
    XCTAssertFalse(failingEnv.offlineMapManager.isStarted, "OfflineMapManager must not start when Phase 1 fails")
    XCTAssertEqual(callCount, 1, "Pending background completion handler must be invoked immediately when bootstrap fails")
    XCTAssertNil(failingEnv.geoGarageChartDownloader, "No background chart downloader must be created when Phase 1 throws")

    // Retrying and failing again must NOT re-invoke the already-drained handler
    await failingEnv.bootstrap()
    XCTAssertEqual(callCount, 1, "Drained background completion handler must not fire twice")
  }

  func testBackgroundSessionCompletion_registeredWhenAlreadyInErrorState_invokesImmediately() async {
    struct SimulatedBootstrapFailure: Error {}

    let failingEnv = AppEnvironment(
      configuration: AppConfiguration(geoGarageClientID: "test_client_id"),
      offlineMapManager: OfflineMapManager(bindsToMapLibreStorage: false),
      partnerSecretService: partnerSecretService,
      authSession: authSession,
      keychainManager: mockKeychain,
      preferencesService: testPreferencesService,
      userDefaults: isolatedDefaults.defaults,
      databaseManager: nil,
      anchorStateStore: MockAppEnvironmentAnchorStateStore(),
      positioningService: MockPositioningService(),
      chartDownloaderSessionConfiguration: MockURLProtocol.makeMockConfiguration()
    )
    failingEnv.databaseManagerFactoryOverride = { throw SimulatedBootstrapFailure() }

    await failingEnv.bootstrap()
    guard case .error = failingEnv.state else {
      XCTFail("Precondition failed: expected .error state")
      return
    }
    XCTAssertFalse(failingEnv.offlineMapManager.isStarted, "OfflineMapManager must remain unstarted on Phase 1 error")

    var callCount = 0
    failingEnv.registerBackgroundURLSessionCompletionHandler {
      callCount += 1
    }

    XCTAssertEqual(callCount, 1, "Handler registered while already in .error state must be invoked immediately instead of leaking")
  }

  // MARK: - Lot 2: Protected Data (BFU) Deferral, Migration & Re-Hydration

  func testBootstrap_inBFULockedState_defersMigrationAndRehydratesOnProtectedDataUnlock() async throws {
    partnerSecretService.secrets = GeoGaragePartnerSecrets(
      clientID: "mock-client",
      customerID: nil,
      packageSecret: "restored-secret",
      teaSecret: ""
    )
    try await mockKeychain.save(token: "bfu_access_token", for: GeoGarageKeychainKeys.accessToken)
    try await mockKeychain.save(token: "cus_bfu_42", for: GeoGarageKeychainKeys.customerID)
    mockKeychain.setStubbedError(.unexpectedStatus(errSecInteractionNotAllowed))

    let protectedDataAvailable = OSAllocatedUnfairLock<Bool>(initialState: false)
    let bfuEnv = AppEnvironment(
      configuration: AppConfiguration(geoGarageClientID: "test_client_id"),
      offlineMapManager: OfflineMapManager(bindsToMapLibreStorage: false),
      partnerSecretService: partnerSecretService,
      authSession: authSession,
      keychainManager: mockKeychain,
      preferencesService: testPreferencesService,
      userDefaults: isolatedDefaults.defaults,
      databaseManager: testDatabaseManager,
      anchorStateStore: MockAppEnvironmentAnchorStateStore(),
      positioningService: MockPositioningService(),
      chartDownloaderSessionConfiguration: MockURLProtocol.makeMockConfiguration(),
      isProtectedDataAvailable: { protectedDataAvailable.withLock { $0 } }
    )

    await bfuEnv.bootstrap()

    guard case .ready(let container) = bfuEnv.state else {
      XCTFail("Expected .ready state even when Keychain is locked in BFU")
      return
    }

    // 1. While locked in BFU: migration not run, migration flag false, no false sign-in warning, no partner secret call
    XCTAssertFalse(isolatedDefaults.defaults.bool(forKey: AppEnvironment.keychainAccessibilityMigratedDefaultsKey))
    XCTAssertTrue(mockKeychain.migrationCalls.isEmpty)
    XCTAssertTrue(bfuEnv.needsProtectedDataHydration)
    XCTAssertTrue(container.geoGarageAuthService.isDeferredForProtectedData)
    XCTAssertTrue(partnerSecretService.receivedAccessTokens.isEmpty, "Must not call /partners/me/ while Keychain is locked")

    // Calling handleProtectedDataDidBecomeAvailable while still locked is a no-op
    await bfuEnv.handleProtectedDataDidBecomeAvailable()
    XCTAssertTrue(bfuEnv.needsProtectedDataHydration)
    XCTAssertTrue(mockKeychain.migrationCalls.isEmpty)

    // 2. Device unlocks: migration runs once, all 3 credentials hydrate, and missing package secret is restored
    protectedDataAvailable.withLock { $0 = true }
    mockKeychain.setStubbedError(nil)

    await bfuEnv.handleProtectedDataDidBecomeAvailable()
    await bfuEnv.packageSecretRestoreTask?.value

    XCTAssertTrue(isolatedDefaults.defaults.bool(forKey: AppEnvironment.keychainAccessibilityMigratedDefaultsKey))
    XCTAssertEqual(mockKeychain.migrationCalls, [GeoGarageKeychainKeys.allAccounts])
    XCTAssertFalse(bfuEnv.needsProtectedDataHydration)
    XCTAssertFalse(container.geoGarageAuthService.isDeferredForProtectedData)
    XCTAssertTrue(container.geoGarageAuthService.isGeoGarageAuthenticated)
    XCTAssertEqual(container.preferencesService.geoGarageCustomerID, "cus_bfu_42")
    XCTAssertEqual(partnerSecretService.receivedAccessTokens, ["bfu_access_token"])

    // 3. Subsequent foreground / unlock notifications are idempotent no-ops
    await bfuEnv.handleProtectedDataDidBecomeAvailable()
    XCTAssertEqual(mockKeychain.migrationCalls.count, 1)
  }

  func testProtectedDataUnlock_duringBootstrap_replaysHydrationAutomaticallyOnReady() async throws {
    try await mockKeychain.save(token: "boot_access_token", for: GeoGarageKeychainKeys.accessToken)
    try await mockKeychain.save(token: "cus_during_boot", for: GeoGarageKeychainKeys.customerID)
    try await mockKeychain.save(token: "secret_during_boot", for: GeoGarageKeychainKeys.packageSecret)
    mockKeychain.setStubbedError(.unexpectedStatus(errSecInteractionNotAllowed))

    let protectedDataAvailable = OSAllocatedUnfairLock<Bool>(initialState: false)
    let (enteredAnchorLoadStream, enteredAnchorLoadContinuation) = AsyncStream<Void>.makeStream()
    let (releaseAnchorLoadStream, releaseAnchorLoadContinuation) = AsyncStream<Void>.makeStream()

    let bfuEnv = AppEnvironment(
      configuration: AppConfiguration(geoGarageClientID: "test_client_id"),
      offlineMapManager: OfflineMapManager(bindsToMapLibreStorage: false),
      partnerSecretService: partnerSecretService,
      authSession: authSession,
      keychainManager: mockKeychain,
      preferencesService: testPreferencesService,
      userDefaults: isolatedDefaults.defaults,
      databaseManager: testDatabaseManager,
      anchorStateStore: MockAppEnvironmentAnchorStateStore(),
      positioningService: MockPositioningService(),
      chartDownloaderSessionConfiguration: MockURLProtocol.makeMockConfiguration(),
      isProtectedDataAvailable: { protectedDataAvailable.withLock { $0 } }
    )
    bfuEnv.anchorStateStoreLoaderOverride = {
      enteredAnchorLoadContinuation.yield()
      enteredAnchorLoadContinuation.finish()
      var iterator = releaseAnchorLoadStream.makeAsyncIterator()
      _ = await iterator.next()
      return MockAppEnvironmentAnchorStateStore()
    }

    let bootstrapTask = Task { @MainActor in
      await bfuEnv.bootstrap()
    }
    defer {
      releaseAnchorLoadContinuation.finish()
    }

    var enteredIterator = enteredAnchorLoadStream.makeAsyncIterator()
    _ = await enteredIterator.next()

    // Protected data unlocks mid-bootstrap (after Keychain reads already failed with errSecInteractionNotAllowed)
    protectedDataAvailable.withLock { $0 = true }
    mockKeychain.setStubbedError(nil)
    await bfuEnv.handleProtectedDataDidBecomeAvailable()

    releaseAnchorLoadContinuation.finish()
    await bootstrapTask.value

    guard case .ready(let container) = bfuEnv.state else {
      XCTFail("Expected .ready state")
      return
    }

    XCTAssertFalse(bfuEnv.needsProtectedDataHydration, "Unlock recorded during .bootstrapping must replay automatically upon .ready")
    XCTAssertTrue(container.geoGarageAuthService.isGeoGarageAuthenticated)
    XCTAssertEqual(container.preferencesService.geoGarageCustomerID, "cus_during_boot")
    XCTAssertEqual(mockKeychain.migrationCalls, [GeoGarageKeychainKeys.allAccounts])
  }

  func testHandleProtectedDataDidBecomeAvailable_isNonReentrantUnderSimultaneousTriggers() async throws {
    let gatingKeychain = GatingMigrationKeychainManager(
      initialTokens: [
        GeoGarageKeychainKeys.accessToken: "reentrant_access",
        GeoGarageKeychainKeys.customerID: "cus_reentrant",
        GeoGarageKeychainKeys.packageSecret: "secret_reentrant"
      ]
    )
    await gatingKeychain.setLocked(true)

    let protectedDataAvailable = OSAllocatedUnfairLock<Bool>(initialState: false)
    let reentrantPrefs = PreferencesService(defaults: isolatedDefaults.defaults, keychainManager: gatingKeychain)
    let bfuEnv = AppEnvironment(
      configuration: AppConfiguration(geoGarageClientID: "test_client_id"),
      offlineMapManager: OfflineMapManager(bindsToMapLibreStorage: false),
      partnerSecretService: partnerSecretService,
      authSession: authSession,
      keychainManager: gatingKeychain,
      preferencesService: reentrantPrefs,
      userDefaults: isolatedDefaults.defaults,
      databaseManager: testDatabaseManager,
      anchorStateStore: MockAppEnvironmentAnchorStateStore(),
      positioningService: MockPositioningService(),
      chartDownloaderSessionConfiguration: MockURLProtocol.makeMockConfiguration(),
      isProtectedDataAvailable: { protectedDataAvailable.withLock { $0 } }
    )

    await bfuEnv.bootstrap()
    XCTAssertTrue(bfuEnv.needsProtectedDataHydration)

    let (enteredMigrationStream, enteredMigrationContinuation) = AsyncStream<Void>.makeStream()
    let (releaseMigrationStream, releaseMigrationContinuation) = AsyncStream<Void>.makeStream()
    await gatingKeychain.installMigrationGate(
      onEnter: enteredMigrationContinuation,
      releaseStream: releaseMigrationStream
    )

    protectedDataAvailable.withLock { $0 = true }
    await gatingKeychain.setLocked(false)

    // First call (`applicationProtectedDataDidBecomeAvailable`) enters hydration and suspends in migration
    let firstCall = Task { @MainActor in
      await bfuEnv.handleProtectedDataDidBecomeAvailable()
    }
    defer {
      releaseMigrationContinuation.finish()
    }

    var enteredIterator = enteredMigrationStream.makeAsyncIterator()
    _ = await enteredIterator.next()

    // Second simultaneous call (`scenePhase == .active`) must bail out immediately via `isHydratingProtectedData`
    await bfuEnv.handleProtectedDataDidBecomeAvailable()

    releaseMigrationContinuation.finish()
    await firstCall.value

    let migrationCount = await gatingKeychain.migrationCallCount
    XCTAssertEqual(migrationCount, 1, "Anti-reentrancy guard must prevent duplicate concurrent hydration passes")
    XCTAssertFalse(bfuEnv.needsProtectedDataHydration)
  }

  func testBootstrap_whenPermanentNonBFUKeychainErrorOccurs_doesNotSetNeedsProtectedDataHydration() async throws {
    mockKeychain.setStubbedError(.decodingFailed)

    let permanentErrorEnv = AppEnvironment(
      configuration: AppConfiguration(geoGarageClientID: "test_client_id"),
      offlineMapManager: OfflineMapManager(bindsToMapLibreStorage: false),
      partnerSecretService: partnerSecretService,
      authSession: authSession,
      keychainManager: mockKeychain,
      preferencesService: testPreferencesService,
      userDefaults: isolatedDefaults.defaults,
      databaseManager: testDatabaseManager,
      anchorStateStore: MockAppEnvironmentAnchorStateStore(),
      positioningService: MockPositioningService(),
      chartDownloaderSessionConfiguration: MockURLProtocol.makeMockConfiguration(),
      isProtectedDataAvailable: { true }
    )

    await permanentErrorEnv.bootstrap()

    guard case .ready(let container) = permanentErrorEnv.state else {
      XCTFail("Expected .ready state")
      return
    }

    XCTAssertFalse(permanentErrorEnv.needsProtectedDataHydration, "Permanent Keychain error must not trigger infinite foreground hydration loops")
    XCTAssertFalse(container.geoGarageAuthService.isDeferredForProtectedData)
    XCTAssertFalse(container.geoGarageAuthService.isGeoGarageAuthenticated)
  }
}

private actor GatingMigrationKeychainManager: KeychainManaging {
  private var tokens: [String: String]
  private var isLocked = false
  private var onEnterMigration: AsyncStream<Void>.Continuation?
  private var releaseMigrationStream: AsyncStream<Void>?
  private(set) var migrationCallCount = 0

  init(initialTokens: [String: String]) {
    self.tokens = initialTokens
  }

  func setLocked(_ locked: Bool) {
    self.isLocked = locked
  }

  func installMigrationGate(
    onEnter: AsyncStream<Void>.Continuation,
    releaseStream: AsyncStream<Void>
  ) {
    self.onEnterMigration = onEnter
    self.releaseMigrationStream = releaseStream
  }

  func save(token: String, for account: String) async throws(KeychainError) {
    if isLocked { throw .unexpectedStatus(errSecInteractionNotAllowed) }
    tokens[account] = token
  }

  func retrieveToken(for account: String) async throws(KeychainError) -> String? {
    if isLocked { throw .unexpectedStatus(errSecInteractionNotAllowed) }
    return tokens[account]
  }

  func deleteToken(for account: String) async throws(KeychainError) {
    if isLocked { throw .unexpectedStatus(errSecInteractionNotAllowed) }
    tokens.removeValue(forKey: account)
  }

  func migrateAccessibilityIfNeeded(for accounts: [String]) async throws(KeychainError) {
    if isLocked { throw .unexpectedStatus(errSecInteractionNotAllowed) }
    migrationCallCount += 1
    if let onEnterMigration, let releaseMigrationStream {
      self.onEnterMigration = nil
      self.releaseMigrationStream = nil
      onEnterMigration.yield()
      onEnterMigration.finish()
      var iterator = releaseMigrationStream.makeAsyncIterator()
      _ = await iterator.next()
    }
  }
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
