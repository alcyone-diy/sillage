//
//  PermissionServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-15.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
import UserNotifications
import os
@testable import Sillage

private nonisolated final class MockNotificationAuthorizationProvider: NotificationAuthorizationProviding, @unchecked Sendable {
  struct EntitlementMissingError: Error {}

  private struct State {
    var settings: NotificationSettingsSnapshot
    var requestedOptionsHistory: [UNAuthorizationOptions] = []
    var shouldThrowOnCriticalAlert = false
    var grantStandardRequest = true
    var grantCriticalRequest = true
  }

  private let stateLock: OSAllocatedUnfairLock<State>

  init(
    settings: NotificationSettingsSnapshot,
    shouldThrowOnCriticalAlert: Bool = false,
    grantStandardRequest: Bool = true,
    grantCriticalRequest: Bool = true
  ) {
    self.stateLock = OSAllocatedUnfairLock(initialState: State(
      settings: settings,
      shouldThrowOnCriticalAlert: shouldThrowOnCriticalAlert,
      grantStandardRequest: grantStandardRequest,
      grantCriticalRequest: grantCriticalRequest
    ))
  }

  var requestedOptionsHistory: [UNAuthorizationOptions] {
    stateLock.withLock { $0.requestedOptionsHistory }
  }

  func notificationSettings() async -> NotificationSettingsSnapshot {
    stateLock.withLock { $0.settings }
  }

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    let result: Result<Bool, Error> = stateLock.withLock { state in
      state.requestedOptionsHistory.append(options)
      if options.contains(.criticalAlert) {
        if state.shouldThrowOnCriticalAlert {
          return .failure(EntitlementMissingError())
        }
        let granted = state.grantCriticalRequest
        state.settings = NotificationSettingsSnapshot(
          authorizationStatus: granted ? .authorized : .denied,
          criticalAlertSetting: granted ? .enabled : .disabled,
          timeSensitiveSetting: granted ? .enabled : state.settings.timeSensitiveSetting
        )
        return .success(granted)
      } else {
        let granted = state.grantStandardRequest
        state.settings = NotificationSettingsSnapshot(
          authorizationStatus: granted ? .authorized : .denied,
          criticalAlertSetting: state.settings.criticalAlertSetting,
          timeSensitiveSetting: granted ? .enabled : state.settings.timeSensitiveSetting
        )
        return .success(granted)
      }
    }
    return try result.get()
  }
}

@MainActor
private final class PermissionTestMockPositioningService: PositioningService {
  var currentAuthorizationStatus: CLAuthorizationStatus = .authorizedAlways
  var currentDistanceFilter: Measurement<UnitLength> = Measurement(value: 10, unit: .meters)
  var lastKnownLocation: NavigationFix?

  var locationUpdates: AsyncStream<PositioningState> {
    AsyncStream.makeStream(of: PositioningState.self).stream
  }

  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> {
    AsyncStream.makeStream(of: CLAuthorizationStatus.self).stream
  }

  func requestAuthorization() {}
  func requestLocationUpdates() -> any LocationUpdateToken {
    final class Token: LocationUpdateToken { func invalidate() {} }
    return Token()
  }
  func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {}
  func removeDistanceFilter(for identifier: String) {}
  func requestBackgroundLocation() -> any BackgroundLocationToken {
    final class Token: BackgroundLocationToken { func invalidate() {} }
    return Token()
  }
}

@MainActor
final class PermissionServiceTests: XCTestCase {

  func testInitialStatuses_mapsCriticalAlertAndTimeSensitiveCapabilities() async throws {
    let provider = MockNotificationAuthorizationProvider(
      settings: NotificationSettingsSnapshot(
        authorizationStatus: .authorized,
        criticalAlertSetting: .notSupported,
        timeSensitiveSetting: .disabled
      )
    )
    let service = PermissionService(
      positioningService: PermissionTestMockPositioningService(),
      notificationService: MockNotificationService(),
      authorizationProvider: provider
    )

    try await waitFor { service.notificationStatus == .authorized }

    XCTAssertEqual(service.criticalAlertStatus, .notSupported)
    XCTAssertEqual(service.timeSensitiveStatus, .disabled)
  }

  func testRequestCriticalNotificationAuthorization_skipsRequestWhenAuthorizedAndUnsupported() async throws {
    let provider = MockNotificationAuthorizationProvider(
      settings: NotificationSettingsSnapshot(
        authorizationStatus: .authorized,
        criticalAlertSetting: .notSupported,
        timeSensitiveSetting: .enabled
      )
    )
    let service = PermissionService(
      positioningService: PermissionTestMockPositioningService(),
      notificationService: MockNotificationService(),
      authorizationProvider: provider
    )

    try await waitFor { service.notificationStatus == .authorized }

    let granted = await service.requestCriticalNotificationAuthorization()
    XCTAssertTrue(granted)
    XCTAssertTrue(provider.requestedOptionsHistory.isEmpty)
    XCTAssertEqual(service.criticalAlertStatus, .notSupported)
    XCTAssertEqual(service.timeSensitiveStatus, .enabled)
  }

  func testRequestCriticalNotificationAuthorization_attemptsOncePerSessionWhenAuthorizedAndCriticalDisabled() async throws {
    let provider = MockNotificationAuthorizationProvider(
      settings: NotificationSettingsSnapshot(
        authorizationStatus: .authorized,
        criticalAlertSetting: .disabled,
        timeSensitiveSetting: .enabled
      ),
      shouldThrowOnCriticalAlert: true
    )
    let service = PermissionService(
      positioningService: PermissionTestMockPositioningService(),
      notificationService: MockNotificationService(),
      authorizationProvider: provider
    )

    try await waitFor { service.notificationStatus == .authorized }

    let firstGranted = await service.requestCriticalNotificationAuthorization()
    let secondGranted = await service.requestCriticalNotificationAuthorization()

    XCTAssertTrue(firstGranted)
    XCTAssertTrue(secondGranted)
    XCTAssertEqual(provider.requestedOptionsHistory.count, 1)
    XCTAssertTrue(provider.requestedOptionsHistory.first?.contains(.criticalAlert) == true)
  }

  func testRequestCriticalNotificationAuthorization_fallsBackToStandardWhenNotDeterminedAndEntitlementMissing() async throws {
    let provider = MockNotificationAuthorizationProvider(
      settings: NotificationSettingsSnapshot(
        authorizationStatus: .notDetermined,
        criticalAlertSetting: .notSupported,
        timeSensitiveSetting: .disabled
      ),
      shouldThrowOnCriticalAlert: true,
      grantStandardRequest: true
    )
    let service = PermissionService(
      positioningService: PermissionTestMockPositioningService(),
      notificationService: MockNotificationService(),
      authorizationProvider: provider
    )

    try await waitFor { service.notificationStatus == .notDetermined }

    let granted = await service.requestCriticalNotificationAuthorization()
    XCTAssertTrue(granted)
    XCTAssertEqual(service.notificationStatus, .authorized)
    XCTAssertEqual(service.timeSensitiveStatus, .enabled)
    XCTAssertEqual(provider.requestedOptionsHistory.count, 2)
    XCTAssertTrue(provider.requestedOptionsHistory[0].contains(.criticalAlert))
    XCTAssertFalse(provider.requestedOptionsHistory[1].contains(.criticalAlert))
  }
}
