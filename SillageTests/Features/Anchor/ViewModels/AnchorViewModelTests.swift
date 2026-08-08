//
//  AnchorViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
private final class AnchorViewModelMockPositioningService: PositioningService {
  private var locationContinuations: [UUID: AsyncStream<PositioningState>.Continuation] = [:]

  var locationUpdates: AsyncStream<PositioningState> {
    let (stream, continuation) = AsyncStream.makeStream(of: PositioningState.self)
    let id = UUID()
    locationContinuations[id] = continuation
    continuation.onTermination = { @Sendable [weak self] _ in
      Task { @MainActor [weak self] in
        self?.locationContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }

  var currentAuthorizationStatus: CLAuthorizationStatus = .authorizedAlways
  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> {
    let (stream, _) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)
    return stream
  }

  var lastKnownLocation: NavigationFix?
  var currentDistanceFilter: Measurement<UnitLength> = Measurement(value: 10, unit: .meters)

  init() {}

  func requestAuthorization() {}

  private final class MockToken: LocationUpdateToken {
    func invalidate() {}
  }

  func requestLocationUpdates() -> any LocationUpdateToken {
    return MockToken()
  }

  func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {}
  func removeDistanceFilter(for identifier: String) {}

  func requestBackgroundLocation() -> any BackgroundLocationToken {
    final class Token: BackgroundLocationToken { func invalidate() {} }
    return Token()
  }

  func simulateFix(_ fix: NavigationFix) {
    self.lastKnownLocation = fix
    for continuation in locationContinuations.values {
      continuation.yield(.active(fix))
    }
  }
}

@MainActor
final class AnchorViewModelTests: XCTestCase {

  func testPreparingDropAnchorLifecycle() async throws {
    let preferencesService = PreferencesService()
    let positioningService = AnchorViewModelMockPositioningService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService
    )
    let viewModel = AnchorViewModel(anchorService: anchorService)

    // 1. Initial State: ephemeral preparation mode is false
    XCTAssertFalse(viewModel.isPreparingDropAnchor)

    // 2. Start preparation mode
    viewModel.startPreparingDropAnchor()
    XCTAssertTrue(viewModel.isPreparingDropAnchor)

    // 3. Cancel preparation mode
    viewModel.cancelPreparingDropAnchor()
    XCTAssertFalse(viewModel.isPreparingDropAnchor)
    XCTAssertEqual(viewModel.state, .setup)

    // 4. Start & Confirm drop anchor
    viewModel.startPreparingDropAnchor()
    XCTAssertTrue(viewModel.isPreparingDropAnchor)

    // Provide fix for dropAnchor via mock positioning service
    let fix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 47.123, longitude: -3.456),
      horizontalAccuracy: Measurement(value: 5.0, unit: UnitLength.meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    positioningService.simulateFix(fix)

    // Allow async location stream in AnchorService to process the fix
    try await Task.sleep(nanoseconds: 100_000_000)

    viewModel.confirmDropAnchor()
    XCTAssertFalse(viewModel.isPreparingDropAnchor)
    XCTAssertEqual(viewModel.state, .dropped)
    XCTAssertNotNil(viewModel.anchorCoordinate)
    XCTAssertEqual(viewModel.anchorCoordinate?.latitude, 47.123)
    XCTAssertEqual(viewModel.anchorCoordinate?.longitude, -3.456)
  }
}
