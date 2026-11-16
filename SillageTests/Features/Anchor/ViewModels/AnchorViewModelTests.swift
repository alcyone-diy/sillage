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

  var isSubscribed: Bool { !locationContinuations.isEmpty }

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

  final class MockToken: LocationUpdateToken {
    private(set) var invalidateCallCount = 0
    func invalidate() {
      invalidateCallCount += 1
    }
  }

  private(set) var requestLocationUpdatesCallCount = 0
  private(set) var lastUpdateToken: MockToken?

  func requestLocationUpdates() -> any LocationUpdateToken {
    requestLocationUpdatesCallCount += 1
    let token = MockToken()
    lastUpdateToken = token
    return token
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
    preferencesService.clearAll()
    let positioningService = AnchorViewModelMockPositioningService()
    let notificationService = MockNotificationService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: notificationService)
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: notificationService,
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: MockAnchorStateStore()
    )
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
    preferencesService.clearAll()
    let positioningService = AnchorViewModelMockPositioningService()
    let notificationService = MockNotificationService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: notificationService)
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: notificationService,
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: MockAnchorStateStore()
    )
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
    viewModel.incrementRadius(locale: usLocale)
    let incrementedFeet = viewModel.configuredRadius.converted(to: .feet).value
    // 82ft rounds to 80ft, then +10ft = 90ft
    XCTAssertEqual(incrementedFeet, 90.0, accuracy: 0.5)

    viewModel.decrementRadius(locale: usLocale)
    let decrementedFeet = viewModel.configuredRadius.converted(to: .feet).value
    // 90ft - 10ft = 80ft
    XCTAssertEqual(decrementedFeet, 80.0, accuracy: 0.5)
  }

  func testDropAnchor_preservesInitialAccuracyFromBestAvailableFix() async throws {
    let preferencesService = MockPreferencesService()
    preferencesService.clearAll()
    let positioningService = AnchorViewModelMockPositioningService()
    let notificationService = MockNotificationService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: notificationService)
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: notificationService,
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: MockAnchorStateStore()
    )
    let viewModel = AnchorViewModel(anchorService: anchorService)

    let degradedFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 47.5, longitude: -3.2),
      horizontalAccuracy: Measurement(value: 28.0, unit: UnitLength.meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    positioningService.lastKnownLocation = degradedFix

    viewModel.dropAnchor()

    try await waitFor(timeout: .seconds(1)) {
      viewModel.state == .dropped && viewModel.initialAccuracy != nil
    }

    XCTAssertEqual(viewModel.initialAccuracy, Measurement(value: 28.0, unit: UnitLength.meters))
  }

  func testApplyState_syncsConfiguredRadiusFromActiveWatch_andResetsToDefaultOnClear() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (anchorService, positioningService, _) = await makeIsolatedAnchorService(directoryURL: tempDir)
    let viewModel = AnchorViewModel(anchorService: anchorService)
    _ = positioningService // Keep mock alive cleanly
    XCTAssertEqual(viewModel.configuredRadius, Measurement(value: 25.0, unit: .meters))

    let coord = CLLocationCoordinate2D(latitude: 47.2, longitude: -1.5)
    let droppedRadius = Measurement<UnitLength>(value: 85.0, unit: .meters)
    anchorService.drop(coordinate: coord, radius: droppedRadius)

    try await waitFor(timeout: .seconds(1)) {
      viewModel.status == .dropped && viewModel.configuredRadius == droppedRadius
    }

    let updatedRadius = Measurement<UnitLength>(value: 120.0, unit: .meters)
    anchorService.update(radius: updatedRadius)

    try await waitFor(timeout: .seconds(1)) {
      viewModel.configuredRadius == updatedRadius
    }

    anchorService.clear()

    try await waitFor(timeout: .seconds(1)) {
      viewModel.status == .inactive && viewModel.configuredRadius == anchorService.defaultRadius
    }
  }

  func testPendingArmAction_clearsOnCancelDrop_externalClear_andSheetDismiss() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (anchorService, positioningService, notificationService) = await makeIsolatedAnchorService(directoryURL: tempDir)
    let coord = CLLocationCoordinate2D(latitude: 47.2, longitude: -1.5)

    // 1. Cancelled via cancelDrop() before permission granted
    anchorService.drop(coordinate: coord, radius: Measurement(value: 50.0, unit: .meters))
    let viewModel = AnchorViewModel(anchorService: anchorService)
    let pendingPermService1 = PermissionService(positioningService: positioningService, notificationService: notificationService)
    viewModel.requestArmAlarm(in: pendingPermService1)
    XCTAssertEqual(viewModel.permissionGateType, .notification(trigger: .anchorAlarm))

    viewModel.cancelDrop()
    XCTAssertNil(viewModel.permissionGateType)
    viewModel.finalizePendingAction()
    XCTAssertEqual(anchorService.status, .inactive)

    // 2. External AnchorService.clear() invalidates pending action via applyState()
    anchorService.drop(coordinate: coord, radius: Measurement(value: 50.0, unit: .meters))
    try await waitFor(timeout: .seconds(1)) {
      viewModel.status == .dropped && viewModel.anchorCoordinate != nil
    }
    let pendingPermService2 = PermissionService(positioningService: positioningService, notificationService: notificationService)
    viewModel.requestArmAlarm(in: pendingPermService2)
    XCTAssertEqual(viewModel.permissionGateType, .notification(trigger: .anchorAlarm))

    anchorService.clear()
    try await waitFor(timeout: .seconds(1)) {
      viewModel.status == .inactive && viewModel.permissionGateType == nil
    }
    viewModel.finalizePendingAction()
    XCTAssertEqual(anchorService.status, .inactive)

    // 3. Sheet dismissal without authorization clears pending action without cancelling the drop
    anchorService.drop(coordinate: coord, radius: Measurement(value: 50.0, unit: .meters))
    try await waitFor(timeout: .seconds(1)) {
      viewModel.status == .dropped && viewModel.anchorCoordinate != nil
    }
    let pendingPermService3 = PermissionService(positioningService: positioningService, notificationService: notificationService)
    viewModel.requestArmAlarm(in: pendingPermService3)
    XCTAssertEqual(viewModel.permissionGateType, .notification(trigger: .anchorAlarm))

    viewModel.handlePermissionSheetDismissed(in: pendingPermService3)
    XCTAssertNil(viewModel.permissionGateType)
    viewModel.finalizePendingAction()
    XCTAssertEqual(anchorService.status, .dropped)

    // 4. Sheet dismissal after permission becomes authorized finalizes pending action and arms idempotently
    let pendingPermService4 = PermissionService(positioningService: positioningService, notificationService: notificationService)
    viewModel.requestArmAlarm(in: pendingPermService4)
    XCTAssertEqual(viewModel.permissionGateType, .notification(trigger: .anchorAlarm))

    pendingPermService4.forceAuthorizedForSimulatedSensors(gps: true, baro: false)
    viewModel.handlePermissionSheetDismissed(in: pendingPermService4)
    XCTAssertNil(viewModel.permissionGateType)
    XCTAssertEqual(anchorService.status, .armed)
  }

  func testRequestArmAlarm_inDroppedPendingPosition_ignoresRequestAndDoesNotOpenGate() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (anchorService, positioningService, notificationService) = await makeIsolatedAnchorService(directoryURL: tempDir)
    anchorService.drop(coordinate: nil, radius: Measurement(value: 45.0, unit: .meters))
    XCTAssertEqual(anchorService.status, .droppedPendingPosition)

    let viewModel = AnchorViewModel(anchorService: anchorService)
    try await waitFor(timeout: .seconds(1)) {
      positioningService.isSubscribed && viewModel.status == .droppedPendingPosition
    }

    let pendingPermService = PermissionService(positioningService: positioningService, notificationService: notificationService)
    viewModel.requestArmAlarm(in: pendingPermService)
    XCTAssertNil(viewModel.permissionGateType)
    viewModel.finalizePendingAction()
    XCTAssertEqual(anchorService.status, .droppedPendingPosition)

    // Subsequent GPS fix fulfills watch to .dropped without stealthily triggering an old arm request
    let fix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 47.4, longitude: -2.1),
      horizontalAccuracy: Measurement(value: 6.0, unit: UnitLength.meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    positioningService.simulateFix(fix)

    try await waitFor(timeout: .seconds(1)) {
      viewModel.status == .dropped && viewModel.anchorCoordinate != nil
    }

    XCTAssertEqual(anchorService.status, .dropped)
    XCTAssertNil(viewModel.permissionGateType)
  }

  func testPendingArmAction_armsWhenFinalizedInValidDroppedState() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (anchorService, positioningService, notificationService) = await makeIsolatedAnchorService(directoryURL: tempDir)
    let coord = CLLocationCoordinate2D(latitude: 47.2, longitude: -1.5)
    anchorService.drop(coordinate: coord, radius: Measurement(value: 50.0, unit: .meters))

    let viewModel = AnchorViewModel(anchorService: anchorService)
    let pendingPermService = PermissionService(positioningService: positioningService, notificationService: notificationService)
    viewModel.requestArmAlarm(in: pendingPermService)
    XCTAssertEqual(viewModel.permissionGateType, .notification(trigger: .anchorAlarm))
    XCTAssertEqual(anchorService.status, .dropped)

    viewModel.finalizePendingAction()
    XCTAssertEqual(anchorService.status, .armed)
  }

  func testCancelDrop_whenSetupModeActive_preservesSetupGPSUpdatesUntilViewDismisses() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (anchorService, positioningService, _) = await makeIsolatedAnchorService(directoryURL: tempDir)
    let viewModel = AnchorViewModel(anchorService: anchorService)

    // Simulate AnchorAlarmView active on screen after an anchor was dropped
    let coord = CLLocationCoordinate2D(latitude: 47.2, longitude: -1.5)
    anchorService.drop(coordinate: coord, radius: Measurement(value: 50.0, unit: .meters))
    viewModel.isSetupModeActive = true
    let setupToken = positioningService.lastUpdateToken
    try await waitFor(timeout: .seconds(1)) {
      positioningService.isSubscribed && viewModel.status == .dropped
    }
    XCTAssertEqual(positioningService.requestLocationUpdatesCallCount, 2) // 1 monitoring + 1 setup
    XCTAssertNotNil(setupToken)

    // Cancelling the drop from the open setup screen must keep setup GPS updates active
    viewModel.cancelDrop()
    try await waitFor(timeout: .seconds(1)) {
      viewModel.status == .inactive
    }
    XCTAssertEqual(setupToken?.invalidateCallCount, 0)
    XCTAssertTrue(positioningService.isSubscribed)

    // Subsequent GPS fix continues updating setup telemetry in .setup state
    let freshFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 47.21, longitude: -1.51),
      horizontalAccuracy: Measurement(value: 4.0, unit: UnitLength.meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    positioningService.simulateFix(freshFix)
    try await waitFor(timeout: .seconds(1)) {
      viewModel.gpsAccuracy == Measurement(value: 4.0, unit: UnitLength.meters)
    }

    // Dismissing AnchorAlarmView releases setup token and stops GPS subscription
    viewModel.isSetupModeActive = false
    try await waitFor(timeout: .seconds(1)) {
      !positioningService.isSubscribed
    }
    XCTAssertEqual(setupToken?.invalidateCallCount, 1)
  }

  func testWeighAnchor_clearsActiveWatchAndPendingArmAction() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (anchorService, positioningService, notificationService) = await makeIsolatedAnchorService(directoryURL: tempDir)
    let coord = CLLocationCoordinate2D(latitude: 47.2, longitude: -1.5)
    anchorService.drop(coordinate: coord, radius: Measurement(value: 50.0, unit: .meters))

    let viewModel = AnchorViewModel(anchorService: anchorService)
    let pendingPermService = PermissionService(positioningService: positioningService, notificationService: notificationService)
    viewModel.requestArmAlarm(in: pendingPermService)
    XCTAssertNotNil(viewModel.permissionGateType)

    viewModel.weighAnchor()
    try await waitFor(timeout: .seconds(1)) {
      viewModel.status == .inactive && viewModel.anchorCoordinate == nil
    }
    XCTAssertNil(viewModel.permissionGateType)
    XCTAssertEqual(anchorService.status, .inactive)
  }

  func testCancelPendingDrop_returnsToSetupAndDeactivatesService() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (anchorService, _, _) = await makeIsolatedAnchorService(directoryURL: tempDir)
    let viewModel = AnchorViewModel(anchorService: anchorService)
    XCTAssertEqual(viewModel.state, .setup)
    XCTAssertEqual(anchorService.status, .inactive)

    viewModel.dropAnchor()
    try await waitFor(timeout: .seconds(1)) { viewModel.state == .droppedPendingPosition }
    XCTAssertEqual(anchorService.status, .droppedPendingPosition)
    XCTAssertNil(anchorService.activeWatch?.coordinate)

    viewModel.cancelDrop()
    try await waitFor(timeout: .seconds(1)) { viewModel.state == .setup && viewModel.anchorCoordinate == nil }
    XCTAssertEqual(anchorService.status, .inactive)
    XCTAssertNil(anchorService.activeWatch)
  }

  func testDisarmAndWeighArmedAnchor_transitionsThroughDroppedToSetup() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (anchorService, _, _) = await makeIsolatedAnchorService(directoryURL: tempDir)
    let viewModel = AnchorViewModel(anchorService: anchorService)
    let coord = CLLocationCoordinate2D(latitude: 47.2, longitude: -1.5)

    anchorService.arm(coordinate: coord, radius: Measurement(value: 50.0, unit: .meters))
    try await waitFor(timeout: .seconds(1)) { viewModel.state == .armed(isDragging: false) }
    XCTAssertEqual(anchorService.status, .armed)

    viewModel.disarmAlarm()
    try await waitFor(timeout: .seconds(1)) { viewModel.state == .dropped }
    XCTAssertEqual(anchorService.status, .dropped)
    if let droppedCoord = anchorService.activeWatch?.coordinate {
      XCTAssertEqual(droppedCoord.latitude, coord.latitude, accuracy: 0.0001)
      XCTAssertEqual(droppedCoord.longitude, coord.longitude, accuracy: 0.0001)
    } else {
      XCTFail("Expected dropped coordinate to remain intact after disarming")
    }

    viewModel.weighAnchor()
    try await waitFor(timeout: .seconds(1)) { viewModel.state == .setup && viewModel.anchorCoordinate == nil }
    XCTAssertEqual(anchorService.status, .inactive)
    XCTAssertNil(anchorService.activeWatch)
  }

  private func makeIsolatedAnchorService(
    directoryURL: URL
  ) async -> (AnchorService, AnchorViewModelMockPositioningService, MockNotificationService) {
    let preferencesService = MockPreferencesService()
    preferencesService.clearAll()
    let positioningService = AnchorViewModelMockPositioningService()
    let notificationService = MockNotificationService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: notificationService)
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let stateStore = await AnchorStateStore.load(directoryURL: directoryURL)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: notificationService,
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: stateStore
    )
    anchorService.clear()
    return (anchorService, positioningService, notificationService)
  }
}
