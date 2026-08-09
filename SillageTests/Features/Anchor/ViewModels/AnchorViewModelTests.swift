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
    let preferencesService = MockPreferencesService()
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
    anchorService.clear()
    let viewModel = AnchorViewModel(anchorService: anchorService)

    // 1. Initial State: ephemeral preparation mode is false
    XCTAssertFalse(viewModel.isPreparingDropAnchor, "Step 1 failed: isPreparingDropAnchor is true")

    // 2. Start preparation mode
    viewModel.startPreparingDropAnchor()
    XCTAssertTrue(viewModel.isPreparingDropAnchor, "Step 2 failed: isPreparingDropAnchor is false")

    // 3. Cancel preparation mode
    viewModel.cancelPreparingDropAnchor()
    XCTAssertFalse(viewModel.isPreparingDropAnchor, "Step 3 failed: isPreparingDropAnchor is true")
    XCTAssertEqual(viewModel.state, .setup, "Step 3 failed: state is \(viewModel.state) instead of .setup")

    // 4. Start & Confirm drop anchor
    viewModel.startPreparingDropAnchor()
    XCTAssertTrue(viewModel.isPreparingDropAnchor, "Step 4 failed: isPreparingDropAnchor is false after start")

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

    viewModel.confirmDropAnchor()

    try await waitFor(timeout: .seconds(1)) {
      viewModel.state == .dropped && viewModel.anchorCoordinate != nil
    }

    XCTAssertFalse(viewModel.isPreparingDropAnchor, "Step 4 failed: isPreparingDropAnchor is true after confirm")
    XCTAssertEqual(viewModel.state, .dropped, "Step 4 failed: state is \(viewModel.state) instead of .dropped")
    XCTAssertNotNil(viewModel.anchorCoordinate, "Step 4 failed: anchorCoordinate is nil")
    XCTAssertEqual(viewModel.anchorCoordinate?.latitude, 47.123, "Step 4 failed: latitude is \(String(describing: viewModel.anchorCoordinate?.latitude))")
    XCTAssertEqual(viewModel.anchorCoordinate?.longitude, -3.456, "Step 4 failed: longitude is \(String(describing: viewModel.anchorCoordinate?.longitude))")
  }

  func testRadiusIncrementAndDecrement() async throws {
    let preferencesService = MockPreferencesService()
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
    anchorService.clear()
    let viewModel = AnchorViewModel(anchorService: anchorService)

    let metricLocale = Locale(components: .init(languageCode: .french, script: nil, languageRegion: .france))
    let usLocale = Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates))

    // 1. Test metric stepping (+5m / -5m)
    let initialMeters = viewModel.configuredRadius.converted(to: .meters).value
    viewModel.incrementRadius(locale: metricLocale)
    let incrementedMeters = viewModel.configuredRadius.converted(to: .meters).value
    XCTAssertEqual(incrementedMeters, initialMeters + 5.0, accuracy: 0.1)

    viewModel.decrementRadius(locale: metricLocale)
    let decrementedMeters = viewModel.configuredRadius.converted(to: .meters).value
    XCTAssertEqual(decrementedMeters, initialMeters, accuracy: 0.1)

    // 2. Test US Imperial stepping (+10ft / -10ft)
    let initialFeet = viewModel.configuredRadius.converted(to: .feet).value // ~82ft for 25m
    viewModel.incrementRadius(locale: usLocale)
    let incrementedFeet = viewModel.configuredRadius.converted(to: .feet).value
    // 82ft rounds to 80ft, then +10ft = 90ft
    XCTAssertEqual(incrementedFeet, 90.0, accuracy: 0.5)

    viewModel.decrementRadius(locale: usLocale)
    let decrementedFeet = viewModel.configuredRadius.converted(to: .feet).value
    // 90ft - 10ft = 80ft
    XCTAssertEqual(decrementedFeet, 80.0, accuracy: 0.5)
  }
}
