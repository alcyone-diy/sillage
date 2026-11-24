//
//  AppDelegateTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-24.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import UIKit
import XCTest
@testable import Sillage

@MainActor
final class AppDelegateTests: XCTestCase {

  private var isolatedDefaults: IsolatedUserDefaults!
  private var mockKeychain: MockKeychainManager!
  private var authSession: URLSession!
  private var databaseManager: DatabaseManager!
  private var environment: AppEnvironment!
  private var sut: AppDelegate!

  override func setUp() async throws {
    try await super.setUp()
    TileProxyProtocol.resetForTesting()
    MockURLProtocol.reset()
    MockURLProtocol.setHandler { request in
      let url = request.url ?? URL(fileURLWithPath: "/")
      let response = HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil) ?? HTTPURLResponse()
      return (response, Data())
    }
    authSession = MockURLProtocol.makeMockSession()
    isolatedDefaults = IsolatedUserDefaults(prefix: "AppDelegateTests")
    mockKeychain = MockKeychainManager()
    let preferences = PreferencesService(defaults: isolatedDefaults.defaults, keychainManager: mockKeychain)
    preferences.clearAll()
    databaseManager = try DatabaseManager.inMemory()

    environment = AppEnvironment(
      configuration: AppConfiguration(geoGarageClientID: "test_client_id"),
      offlineMapManager: OfflineMapManager(bindsToMapLibreStorage: false),
      partnerSecretService: MockGeoGaragePartnerSecretService(),
      authSession: authSession,
      keychainManager: mockKeychain,
      preferencesService: preferences,
      userDefaults: isolatedDefaults.defaults,
      databaseManager: databaseManager,
      anchorStateStore: MockAppEnvironmentAnchorStateStore(),
      positioningService: MockPositioningService(),
      chartDownloaderSessionConfiguration: MockURLProtocol.makeMockConfiguration()
    )
    sut = AppDelegate(environment: environment)
  }

  override func tearDown() async throws {
    sut = nil
    environment = nil
    databaseManager = nil
    isolatedDefaults?.tearDown()
    isolatedDefaults = nil
    mockKeychain = nil
    authSession = nil
    MockURLProtocol.reset()
    TileProxyProtocol.resetForTesting()
    try await super.tearDown()
  }

  func testHandleEventsForBackgroundURLSession_unknownIdentifier_invokesCompletionImmediately() {
    var completionCount = 0

    sut.application(
      UIApplication.shared,
      handleEventsForBackgroundURLSession: "com.unknown.background.session"
    ) {
      completionCount += 1
    }

    XCTAssertEqual(completionCount, 1, "Unknown session identifiers must invoke completionHandler immediately")
    if case .uninitialized = environment.state {
      // Expected: unknown identifier must not mutate environment state
    } else {
      XCTFail("Environment state must remain .uninitialized")
    }
  }

  func testHandleEventsForBackgroundURLSession_geoGarageIdentifier_routesHandlerThroughBootstrap() async throws {
    let completed = expectation(description: "Background URLSession completion routed from AppDelegate to GeoGarageChartDownloader")
    var completionCount = 0

    sut.application(
      UIApplication.shared,
      handleEventsForBackgroundURLSession: GeoGarageChartDownloader.backgroundSessionIdentifier
    ) {
      completionCount += 1
      completed.fulfill()
    }

    await sut.bootstrapEnvironmentAndDrainNotifications()
    let downloader = try XCTUnwrap(environment.geoGarageChartDownloader)
    downloader.urlSessionDidFinishEvents(forBackgroundURLSession: authSession)

    await fulfillment(of: [completed], timeout: 2.0)
    XCTAssertEqual(completionCount, 1)
  }

  func testRouteNotificationIdentifier_bufferedBeforeReady_drainsOnceBootstrapCompletes() async {
    sut.routeNotificationIdentifier(NotificationIntent.barometerDrop.rawValue)

    await sut.bootstrapEnvironmentAndDrainNotifications()

    guard case .ready(let container) = environment.state else {
      XCTFail("Expected environment to reach .ready")
      return
    }

    // Navigation intent remains deferred until UI mounts (`isReady = true`)
    XCTAssertNil(container.appViewModel.pendingNotificationIntent)
    container.appViewModel.isReady = true
    container.appViewModel.processDeferredIntent()
    XCTAssertEqual(container.appViewModel.pendingNotificationIntent, .barometerDrop)
  }

  func testRouteNotificationIdentifier_whenAlreadyReady_forwardsDirectlyToAppViewModel() async {
    await sut.bootstrapEnvironmentAndDrainNotifications()
    guard case .ready(let container) = environment.state else {
      XCTFail("Expected environment to reach .ready")
      return
    }
    container.appViewModel.isReady = true

    sut.routeNotificationIdentifier(NotificationIntent.anchorDragging.rawValue)

    XCTAssertEqual(container.appViewModel.pendingNotificationIntent, .anchorDragging)
  }
}
