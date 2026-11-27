//
//  AppDelegateTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-24.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import os
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
    TileProxyURLProtocol.resetForTesting()
    MockURLProtocol.reset()
    MockURLProtocol.setHandler { request in
      let url = request.url ?? URL(fileURLWithPath: "/")
      let response = HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil) ?? HTTPURLResponse()
      return (response, Data())
    }
    authSession = MockURLProtocol.makeMockSession()
    isolatedDefaults = IsolatedUserDefaults(prefix: "AppDelegateTests")
    mockKeychain = MockKeychainManager()
    databaseManager = try DatabaseManager.inMemory()

    environment = AppEnvironment(overrides: try makeFixtureOverrides())
    sut = AppDelegate(environment: environment)
  }

  private func makeFixtureOverrides() throws -> AppEnvironment.Overrides {
    var overrides = try makeTestOverrides(userDefaults: isolatedDefaults.defaults)
    overrides.authSession = authSession
    overrides.keychainManager = mockKeychain
    overrides.useDatabaseManager(databaseManager)
    return overrides
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
    TileProxyURLProtocol.resetForTesting()
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
    guard case .ready(let container) = environment.state else {
      XCTFail("Expected environment to reach .ready")
      return
    }
    container.geoGarageChartDownloader.urlSessionDidFinishEvents(forBackgroundURLSession: authSession)

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

  func testProcessProtectedDataAvailabilityChange_whenEnvironmentFailedInBFU_retriesBootstrapAndDrainsPendingNotification() async throws {
    struct TransientBFUDatabaseError: Error {}

    let protectedDataAvailable = OSAllocatedUnfairLock<Bool>(initialState: false)
    let shouldFailDBLock = OSAllocatedUnfairLock<Bool>(initialState: true)
    let validDB = try XCTUnwrap(self.databaseManager)
    var overrides = try makeFixtureOverrides()
    overrides.isProtectedDataAvailable = { protectedDataAvailable.withLock { $0 } }
    overrides.databaseManagerFactory = {
      if shouldFailDBLock.withLock({ $0 }) {
        throw TransientBFUDatabaseError()
      }
      return validDB
    }
    let recoverableEnv = AppEnvironment(overrides: overrides)

    let delegate = AppDelegate(environment: recoverableEnv)
    delegate.routeNotificationIdentifier(NotificationIntent.barometerDrop.rawValue)

    // 1. Initial boot fails while locked (`protectedDataAvailable == false`) -> records BFU failure
    await delegate.bootstrapEnvironmentAndDrainNotifications()
    guard case .error = recoverableEnv.state else {
      XCTFail("Expected .error state on initial BFU failure")
      return
    }
    XCTAssertTrue(recoverableEnv.didFailWhileProtectedDataUnavailable)

    // Calling while still locked must be a no-op
    await delegate.processProtectedDataAvailabilityChange()
    if case .error = recoverableEnv.state {
      // Expected: still locked
    } else {
      XCTFail("Must not retry while protected data is still unavailable")
    }

    // 2. Protected data unlocks -> `processProtectedDataAvailabilityChange()` retries bootstrap and drains notification
    protectedDataAvailable.withLock { $0 = true }
    shouldFailDBLock.withLock { $0 = false }
    await delegate.processProtectedDataAvailabilityChange()

    guard case .ready(let container) = recoverableEnv.state else {
      XCTFail("Expected .ready state after protected data unlock retry")
      return
    }

    container.appViewModel.isReady = true
    container.appViewModel.processDeferredIntent()
    XCTAssertEqual(container.appViewModel.pendingNotificationIntent, .barometerDrop)
  }

  func testProcessProtectedDataAvailabilityChange_whenFailedWhileUnlocked_doesNotAutoRetryBootstrap() async throws {
    struct PermanentUnlockedDatabaseError: Error {}

    let attemptCountLock = OSAllocatedUnfairLock<Int>(initialState: 0)
    var overrides = try makeFixtureOverrides()
    overrides.isProtectedDataAvailable = { true }
    overrides.databaseManagerFactory = {
      attemptCountLock.withLock { $0 += 1 }
      throw PermanentUnlockedDatabaseError()
    }
    let unlockedFailingEnv = AppEnvironment(overrides: overrides)

    let delegate = AppDelegate(environment: unlockedFailingEnv)
    await delegate.bootstrapEnvironmentAndDrainNotifications()

    guard case .error = unlockedFailingEnv.state else {
      XCTFail("Expected .error state")
      return
    }
    XCTAssertFalse(unlockedFailingEnv.didFailWhileProtectedDataUnavailable)
    XCTAssertEqual(attemptCountLock.withLock({ $0 }), 1)

    // Returning `.active` (e.g. closing Control Center on SplashView) must NOT trigger a retry loop
    await delegate.processProtectedDataAvailabilityChange()
    XCTAssertEqual(attemptCountLock.withLock({ $0 }), 1, "Failures occurring while unlocked must only retry on explicit user tap")
    if case .error = unlockedFailingEnv.state {
      // Expected: remains on SplashView error state
    } else {
      XCTFail("Expected state to remain .error")
    }
  }
}
