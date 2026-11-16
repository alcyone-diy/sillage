//
//  AnchorServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
final class MockBackgroundLocationToken: BackgroundLocationToken {
  var isInvalidated = false
  func invalidate() { isInvalidated = true }
}

@MainActor
final class MockPositioningService: PositioningService {
  struct LocationContinuationWrapper: Sendable {
    weak var service: MockPositioningService?
    
    @discardableResult
    @MainActor
    func yield(_ value: PositioningState) -> AsyncStream<PositioningState>.Continuation.YieldResult {
      service?.yieldLocation(value)
      return .enqueued(remaining: 0)
    }
    
    @MainActor
    func finish() {
      service?.finishLocationStreams()
    }
  }

  struct AuthContinuationWrapper: Sendable {
    weak var service: MockPositioningService?
    
    @discardableResult
    @MainActor
    func yield(_ value: CLAuthorizationStatus) -> AsyncStream<CLAuthorizationStatus>.Continuation.YieldResult {
      service?.yieldAuth(value)
      return .enqueued(remaining: 0)
    }
  }

  private var locationContinuations: [UUID: AsyncStream<PositioningState>.Continuation] = [:]
  private var authContinuations: [UUID: AsyncStream<CLAuthorizationStatus>.Continuation] = [:]

  private(set) var locationUpdatesAccessCount = 0

  private var bufferedStates: [PositioningState] = []

  var isSubscribed: Bool {
    !locationContinuations.isEmpty
  }

  var locationUpdates: AsyncStream<PositioningState> {
    locationUpdatesAccessCount += 1
    let (stream, continuation) = AsyncStream.makeStream(of: PositioningState.self)
    let id = UUID()
    locationContinuations[id] = continuation
    for state in bufferedStates {
      continuation.yield(state)
    }
    bufferedStates.removeAll()
    continuation.onTermination = { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.locationContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }

  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> {
    let (stream, continuation) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)
    let id = UUID()
    authContinuations[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.authContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }

  var locationContinuation: LocationContinuationWrapper?
  var currentDistanceFilter: Measurement<UnitLength> = Measurement(value: 10, unit: .meters)
  
  var currentAuthorizationStatus: CLAuthorizationStatus = .notDetermined
  
  var authContinuation: AuthContinuationWrapper?
  
  var lastKnownLocation: NavigationFix?
  
  init() {
    self.locationContinuation = LocationContinuationWrapper(service: self)
    self.authContinuation = AuthContinuationWrapper(service: self)
  }

  func yieldLocation(_ state: PositioningState) {
    if locationContinuations.isEmpty {
      bufferedStates.append(state)
    } else {
      for continuation in locationContinuations.values {
        continuation.yield(state)
      }
    }
  }

  func yieldAuth(_ status: CLAuthorizationStatus) {
    self.currentAuthorizationStatus = status
    for continuation in authContinuations.values {
      continuation.yield(status)
    }
  }

  func finishLocationStreams() {
    bufferedStates.removeAll()
    for continuation in locationContinuations.values {
      continuation.finish()
    }
    locationContinuations.removeAll()
  }
  
  func requestAuthorization() {}
  final class MockLocationUpdateToken: LocationUpdateToken {
    private(set) var invalidateCallCount = 0
    func invalidate() {
      invalidateCallCount += 1
    }
  }
  private(set) var requestLocationUpdatesCallCount = 0
  private(set) var lastUpdateToken: MockLocationUpdateToken?

  func requestLocationUpdates() -> any LocationUpdateToken {
    requestLocationUpdatesCallCount += 1
    let token = MockLocationUpdateToken()
    lastUpdateToken = token
    return token
  }
  
  func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {}
  func removeDistanceFilter(for identifier: String) {}
  
  var requestedToken: MockBackgroundLocationToken?
  func requestBackgroundLocation() -> any BackgroundLocationToken {
    let token = MockBackgroundLocationToken()
    requestedToken = token
    return token
  }
  
  func simulateFix(_ fix: NavigationFix) {
    lastKnownLocation = fix
    locationContinuation?.yield(.active(fix))
  }
}



@MainActor
final class MockBackgroundMonitoringToken: BackgroundMonitoringToken {
  var isInvalidated = false
  func invalidate() { isInvalidated = true }
}

@MainActor
final class MockBackgroundMonitoringService: BackgroundMonitoringService {
  var requestedToken: MockBackgroundMonitoringToken?
  func startMonitoring(ownerIdentifier: String, distanceFilter: Measurement<UnitLength>) -> any BackgroundMonitoringToken {
    let token = MockBackgroundMonitoringToken()
    requestedToken = token
    return token
  }
}

@MainActor
final class MockPermissionService: PermissionServiceProtocol {
    var locationStatus: PermissionStatus = .unknown
    var notificationStatus: PermissionStatus = .unknown
    var criticalAlertStatus: NotificationAlertCapabilityStatus = .unknown
    var timeSensitiveStatus: NotificationAlertCapabilityStatus = .unknown
    var motionStatus: PermissionStatus = .unknown
    
    var requestLocationAuthorizationCalled = false
    func requestLocationAuthorization() async {
        requestLocationAuthorizationCalled = true
    }
    
    var requestNotificationAuthorizationResult = true
    func requestNotificationAuthorization() async -> Bool {
        return requestNotificationAuthorizationResult
    }
    
    var requestCriticalNotificationAuthorizationResult = true
    func requestCriticalNotificationAuthorization() async -> Bool {
        return requestCriticalNotificationAuthorizationResult
    }
    
    var openSystemSettingsCalled = false
    func openSystemSettings() {
        openSystemSettingsCalled = true
    }
    
    var requestMotionAuthorizationCalled = false
    func requestMotionAuthorization() async {
        requestMotionAuthorizationCalled = true
    }
}
final class MockAnchorStateStore: AnchorStateStoreProtocol, @unchecked Sendable {
  var session = AnchorSessionData()
  func loadSession() -> AnchorSessionData { session }
  func saveSession(_ session: AnchorSessionData) { self.session = session }
}

@MainActor
final class MockAlarmAudioService: AlarmAudioServiceProtocol {
  private(set) var startSirenCallCount = 0
  private(set) var stopSirenCallCount = 0
  private(set) var isPlaying = false

  func prepareAudioSession() {}

  func startSiren() {
    startSirenCallCount += 1
    isPlaying = true
  }

  func stopSiren() {
    stopSirenCallCount += 1
    isPlaying = false
  }
}

@MainActor
final class AnchorServiceTests: XCTestCase {
  
  var service: AnchorService!
  var mockGPS: MockPositioningService!
  var mockPrefs: MockPreferencesService!
  var mockNotif: MockNotificationService!
  var mockPermission: MockPermissionService!
  var mockMonitoring: MockBackgroundMonitoringService!
  var mockStateStore: MockAnchorStateStore!
  var mockAudio: MockAlarmAudioService!
  
  override func setUp() async throws {
    try await super.setUp()
    mockGPS = MockPositioningService()
    mockPrefs = MockPreferencesService()
    mockPrefs.clearAll()
    mockNotif = MockNotificationService()
    mockPermission = MockPermissionService()
    mockMonitoring = MockBackgroundMonitoringService()
    mockStateStore = MockAnchorStateStore()
    mockAudio = MockAlarmAudioService()
    service = AnchorService(
      positioningService: mockGPS,
      preferencesService: mockPrefs,
      notificationService: mockNotif,
      permissionService: mockPermission,
      backgroundMonitoringService: mockMonitoring,
      alarmAudioService: mockAudio,
      stateStore: mockStateStore
    )
    try await waitFor { self.mockGPS.isSubscribed }
  }
  
  func testAnchorService_triggersAlarm_InvalidAccuracy_MinusOne() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    
    // Simulate a fix with INVALID accuracy (-1) while armed
    let badFixCoord = CLLocationCoordinate2D(latitude: 45.001, longitude: -1.0)
    let badFix = NavigationFix(
      coordinate: badFixCoord,
      horizontalAccuracy: Measurement(value: -1.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(badFix)
    try await waitFor { service.status == .dragging }
    
    // Status must change to .dragging with .gpsSignalLost trigger reason
    XCTAssertEqual(service.status, .dragging)
    XCTAssertEqual(service.triggerReason, .gpsSignalLost)
  }
  
  func testAnchorService_triggersAlarm_PoorAccuracy() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    
    // Simulate a fix with DEGRADED accuracy (> 25m) while armed
    let degradedFixCoord = CLLocationCoordinate2D(latitude: 45.001, longitude: -1.0)
    let degradedFix = NavigationFix(
      coordinate: degradedFixCoord,
      horizontalAccuracy: Measurement(value: 26.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(degradedFix)
    try await waitFor { service.status == .dragging }
    
    // Status must change to dragging with poorAccuracy reason
    XCTAssertEqual(service.status, .dragging)
    if case .poorAccuracy(let acc, let req) = service.triggerReason {
      XCTAssertEqual(acc.value, 26.0)
      XCTAssertEqual(req.value, 25.0)
    } else {
      XCTFail("Expected .poorAccuracy trigger reason")
    }
  }
  
  func testAnchorService_triggersAlarm_ValidAccuracy() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    
    // Simulate a fix OUTSIDE the radius with VALID accuracy (<= 25m)
    let validFixCoord = CLLocationCoordinate2D(latitude: 45.001, longitude: -1.0) // ~111m away
    let validFix = NavigationFix(
      coordinate: validFixCoord,
      horizontalAccuracy: Measurement(value: 10.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(validFix)
    try await waitFor { service.status == .dragging && mockNotif.sentNotifications.count == 1 }
    
    // Status must change to dragging
    XCTAssertEqual(service.status, .dragging)
    if case .distanceExceeded(_, let rad) = service.triggerReason {
      XCTAssertEqual(rad.value, 50.0)
    } else {
      XCTFail("Expected .distanceExceeded trigger reason")
    }
    XCTAssertEqual(mockNotif.sentNotifications.count, 1)
    XCTAssertEqual(mockNotif.sentNotifications.first?.title, String(localized: "⚓️ DRAGGING ANCHOR!"))
    let body = try XCTUnwrap(mockNotif.sentNotifications.first?.body)
    let expectedRadius = Measurement(value: 50, unit: UnitLength.meters).marineAnchorDistanceFormatted()
    XCTAssertTrue(
      body.contains(expectedRadius),
      "Expected notification body '\(body)' to contain formatted radius '\(expectedRadius)'"
    )
  }

  func testAnchorService_triggersAlarm_GPSSignalLost() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    
    struct GPSTestError: Error {}
    mockGPS.locationContinuation?.yield(.lost(GPSTestError()))
    try await waitFor { service.status == .dragging }
    
    XCTAssertEqual(service.status, .dragging)
    XCTAssertEqual(service.triggerReason, .gpsSignalLost)
  }
  
  func testAnchorService_silenceAlarm_preventsNotifications_and_resetsOnReturn() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    
    // Simulate valid fix outside radius
    let validFixCoord = CLLocationCoordinate2D(latitude: 45.001, longitude: -1.0) // ~111m away
    let validFix = NavigationFix(
      coordinate: validFixCoord,
      horizontalAccuracy: Measurement(value: 10.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(validFix)
    try await waitFor { service.status == .dragging && mockNotif.sentNotifications.count == 1 }
    
    XCTAssertEqual(service.status, .dragging)
    XCTAssertEqual(mockNotif.sentNotifications.count, 1)
    
    // Silence the alarm
    service.silenceAlarm()
    XCTAssertTrue(service.isMuted)
    
    // Simulate another fix outside the radius
    let furtherFixCoord = CLLocationCoordinate2D(latitude: 45.002, longitude: -1.0)
    let furtherFix = NavigationFix(
      coordinate: furtherFixCoord,
      horizontalAccuracy: Measurement(value: 10.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(furtherFix)
    try await waitFor { (service.currentDistance?.value ?? 0) > 200.0 }
    
    // Notification shouldn't trigger again because it is muted (and already dragging)
    XCTAssertEqual(service.status, .dragging)
    XCTAssertEqual(mockNotif.sentNotifications.count, 1)
    
    // Return inside radius
    let returnFixCoord = CLLocationCoordinate2D(latitude: 45.0001, longitude: -1.0) // ~11m away
    let returnFix = NavigationFix(
      coordinate: returnFixCoord,
      horizontalAccuracy: Measurement(value: 10.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(returnFix)
    try await waitFor { service.status == .armed }
    
    XCTAssertEqual(service.status, .armed)
    XCTAssertFalse(service.isMuted) // Mute flag should be reset
    
    // Go back outside
    mockGPS.simulateFix(validFix)
    try await waitFor { service.status == .dragging && mockNotif.sentNotifications.count == 2 }
    
    XCTAssertEqual(service.status, .dragging)
    XCTAssertEqual(mockNotif.sentNotifications.count, 2) // Notification triggers again!
  }
  
  func testAnchorService_disarmRevertsToDropped_clearRevertsToInactive() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    
    // 1. Drop anchor
    service.drop(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    XCTAssertEqual(service.status, .dropped)
    XCTAssertNotNil(service.activeWatch)
    
    // 2. Arm alarm
    service.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    XCTAssertEqual(service.status, .armed)
    XCTAssertNotNil(service.activeWatch)
    
    // 3. Disarm alarm
    service.disarm()
    XCTAssertEqual(service.status, .dropped, "Disarming should revert status to .dropped")
    XCTAssertNotNil(service.activeWatch, "Disarming should keep the active watch (coordinate and radius)")
    XCTAssertEqual(service.activeWatch?.coordinate?.latitude, 45.0)
    
    // 4. Clear anchor drop
    service.clear()
    XCTAssertEqual(service.status, .inactive, "Clearing should revert status to .inactive")
    XCTAssertNil(service.activeWatch, "Clearing should remove the active watch")
  }
  
  func testAnchorService_updateRadius_modifiesActiveWatchWithoutChangingStatus() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.drop(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    XCTAssertEqual(service.status, .dropped)
    
    // Update radius
    let newRadius = Measurement(value: 100, unit: UnitLength.meters)
    service.update(radius: newRadius)
    
    // Assert status hasn't changed, but radius has
    XCTAssertEqual(service.status, .dropped)
    XCTAssertEqual(service.activeWatch?.radius.value, 100)
    XCTAssertEqual(service.activeWatch?.coordinate?.latitude, 45.0)
  }
  
  func testAnchorService_droppedState_updatesDistanceButNeverTriggersAlarm() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    
    // Drop but DO NOT arm
    service.drop(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    
    // Simulate a fix OUTSIDE the radius (e.g. 111m away) with valid accuracy
    let outsideFixCoord = CLLocationCoordinate2D(latitude: 45.001, longitude: -1.0)
    let fix = NavigationFix(
      coordinate: outsideFixCoord,
      horizontalAccuracy: Measurement(value: 10.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    mockGPS.locationContinuation?.yield(.active(fix))
    try await waitFor { service.currentDistance != nil }
    
    // The distance MUST be calculated and updated
    XCTAssertNotNil(service.currentDistance)
    XCTAssertTrue(service.currentDistance!.value > 50.0)
    
    // The status MUST remain .dropped and NO notification should be sent
    XCTAssertEqual(service.status, .dropped)
    XCTAssertEqual(mockNotif.sentNotifications.count, 0)
  }
  
  func testAnchorService_initialization_resumesDroppedStateCorrectly() async throws {
    // Setup stateStore to simulate an app launch with an existing "dropped" anchor
    let savedCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    let stateStore = MockAnchorStateStore()
    stateStore.session = AnchorSessionData(
      activeWatch: AnchorWatch(coordinate: savedCoord, radius: Measurement(value: 60, unit: .meters)),
      status: .dropped,
      triggerReason: nil
    )
    
    // Re-initialize a new service with this mock state store
    let newService = AnchorService(
      positioningService: mockGPS,
      preferencesService: mockPrefs,
      notificationService: mockNotif,
      permissionService: mockPermission,
      backgroundMonitoringService: mockMonitoring,
      alarmAudioService: mockAudio,
      stateStore: stateStore
    )
    
    XCTAssertEqual(newService.status, .dropped)
    XCTAssertNotNil(newService.activeWatch)
    XCTAssertEqual(newService.activeWatch?.radius.value, 60)
    
    // Must also have requested background location to compute live distance
    XCTAssertNotNil(mockMonitoring.requestedToken)
  }
  
  func testAnchorService_bestAvailableFix_enforces60sTTL() async throws {
    // 1. Setup lastKnownLocation older than 60 seconds (e.g. 120 seconds old)
    let oldDate = Date().addingTimeInterval(-120)
    let oldFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 47.0, longitude: -2.0),
      horizontalAccuracy: Measurement(value: 10, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: oldDate
    )
    mockGPS.lastKnownLocation = oldFix
    
    // Assert bestAvailableFix returns nil because fix is expired (120s > 60s)
    XCTAssertNil(service.bestAvailableFix)
    
    // 2. Setup fresh lastKnownLocation (30 seconds old)
    let freshDate = Date().addingTimeInterval(-30)
    let freshFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 47.0, longitude: -2.0),
      horizontalAccuracy: Measurement(value: 10, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: freshDate
    )
    mockGPS.lastKnownLocation = freshFix
    
    // Assert bestAvailableFix returns freshFix
    XCTAssertEqual(service.bestAvailableFix?.coordinate.latitude, 47.0)
  }
  
  func testAnchorService_dropWithoutFix_transitionsToDroppedPendingPosition_andFulfillsOnFirstFix() async throws {
    // 1. Drop anchor when no GPS fix is available
    mockGPS.lastKnownLocation = nil
    service.drop(coordinate: nil, radius: Measurement(value: 40, unit: .meters))
    
    // Status must be .droppedPendingPosition and coordinate must be nil
    XCTAssertEqual(service.status, .droppedPendingPosition)
    XCTAssertNil(service.activeWatch?.coordinate)
    
    // 2. Simulate first incoming GPS fix
    let firstFixCoord = CLLocationCoordinate2D(latitude: 48.0, longitude: -3.0)
    let firstFix = NavigationFix(
      coordinate: firstFixCoord,
      horizontalAccuracy: Measurement(value: 18.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    mockGPS.simulateFix(firstFix)
    try await waitFor { service.status == .dropped }
    
    // Status must now be .dropped with coordinate locked
    XCTAssertEqual(service.status, .dropped)
    XCTAssertEqual(service.activeWatch?.coordinate?.latitude, 48.0)
    XCTAssertEqual(service.activeWatch?.initialAccuracy?.value, 18.0)
  }
  
  func testAnchorService_dropWithDegradedAccuracy_persistsInitialAccuracy() async throws {
    let degradedFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 49.0, longitude: -4.0),
      horizontalAccuracy: Measurement(value: 65.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    service.drop(
      coordinate: degradedFix.coordinate,
      radius: Measurement(value: 50, unit: .meters),
      initialAccuracy: degradedFix.horizontalAccuracy
    )
    
    XCTAssertEqual(service.status, .dropped)
    XCTAssertEqual(service.activeWatch?.coordinate?.latitude, 49.0)
    XCTAssertEqual(service.activeWatch?.initialAccuracy, Measurement(value: 65.0, unit: .meters))

    // Also verify nil coordinate resolves initialAccuracy from bestAvailableFix
    service.clear()
    mockGPS.lastKnownLocation = degradedFix
    service.drop(coordinate: nil, radius: Measurement(value: 50, unit: .meters))
    XCTAssertEqual(service.status, .dropped)
    XCTAssertEqual(service.activeWatch?.initialAccuracy, Measurement(value: 65.0, unit: .meters))
  }
  
  func testAnchorService_adjustAnchorPosition_updatesCoordinate_clearsInitialAccuracy_andRecalculatesDistance() async throws {
    let initialFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0),
      horizontalAccuracy: Measurement(value: 30.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    // 1. Drop anchor with initial accuracy 30m
    service.drop(coordinate: initialFix.coordinate, radius: Measurement(value: 50, unit: .meters))
    mockGPS.simulateFix(initialFix)
    try await waitFor { service.status == .dropped && service.currentDistance != nil }
    
    XCTAssertEqual(service.status, .dropped)
    
    // 2. Adjust anchor position manually
    let newCoord = CLLocationCoordinate2D(latitude: 45.0005, longitude: -1.0)
    service.adjustAnchorPosition(to: newCoord)
    
    // Verify coordinate updated
    XCTAssertEqual(service.activeWatch?.coordinate?.latitude, 45.0005)
    // Verify initialAccuracy reset to nil
    XCTAssertNil(service.activeWatch?.initialAccuracy)
    // Verify status maintained
    XCTAssertEqual(service.status, .dropped)
    // Verify distance recalculated immediately
    XCTAssertNotNil(service.currentDistance)
  }
  
  func testAnchorService_adjustAnchorPosition_whenArmed_maintainsArmedStatus_andRecalculatesDistance() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    
    let fix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 45.0001, longitude: -1.0),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    mockGPS.simulateFix(fix)
    try await waitFor { service.status == .armed && service.currentDistance != nil }
    
    XCTAssertEqual(service.status, .armed)
    
    // Adjust position while armed
    let adjustedCoord = CLLocationCoordinate2D(latitude: 45.0002, longitude: -1.0)
    service.adjustAnchorPosition(to: adjustedCoord)
    
    XCTAssertEqual(service.status, .armed, "Status must remain .armed after manual adjustment")
    XCTAssertEqual(service.activeWatch?.coordinate?.latitude, 45.0002)
    XCTAssertNil(service.activeWatch?.initialAccuracy)
    XCTAssertNotNil(service.currentDistance)
  }

  func testAnchorService_adjustAnchorPosition_whenNoGPSFix_updatesCoordinate_andLeavesDistanceNil() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.drop(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    
    XCTAssertEqual(service.status, .dropped)
    
    // Adjust position without any incoming GPS fix
    let adjustedCoord = CLLocationCoordinate2D(latitude: 45.001, longitude: -1.0)
    service.adjustAnchorPosition(to: adjustedCoord)
    
    XCTAssertEqual(service.activeWatch?.coordinate?.latitude, 45.001)
    XCTAssertNil(service.activeWatch?.initialAccuracy)
    XCTAssertNil(service.currentDistance)
  }

  func testAnchorService_cancelsLocationTask_whenSetupStopsAndInactive() async throws {
    service.startSetupLocationUpdates()
    XCTAssertEqual(mockGPS.requestLocationUpdatesCallCount, 1)
    
    service.stopSetupLocationUpdates()
    XCTAssertEqual(mockGPS.lastUpdateToken?.invalidateCallCount, 1)
    XCTAssertEqual(service.status, .inactive)
  }

  func testAnchorService_dropAndArmRestartGPSListening_afterClear() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.clear()
    try await waitFor { !self.mockGPS.isSubscribed }

    // 1. drop() must restart GPS listening after clear()
    service.drop(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    try await waitFor { self.mockGPS.isSubscribed }

    let droppedFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 45.0001, longitude: -1.0),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    mockGPS.simulateFix(droppedFix)
    try await waitFor { self.service.currentDistance != nil }

    // 2. arm() must also restart GPS listening after clear()
    service.clear()
    try await waitFor { !self.mockGPS.isSubscribed }

    service.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    try await waitFor { self.mockGPS.isSubscribed }

    let draggingFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 45.001, longitude: -1.0),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    mockGPS.simulateFix(draggingFix)
    try await waitFor { self.service.status == .dragging }
    XCTAssertEqual(service.status, .dragging)
  }

  func testAnchorService_clearPreservingSetupUpdates_keepsTokenAndGPSListeningActive() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.startSetupLocationUpdates()
    let setupToken = mockGPS.lastUpdateToken
    XCTAssertEqual(mockGPS.requestLocationUpdatesCallCount, 1)
    XCTAssertNotNil(setupToken)

    service.drop(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    service.clear()

    XCTAssertEqual(service.status, .inactive)
    XCTAssertNil(service.activeWatch)
    XCTAssertEqual(setupToken?.invalidateCallCount, 0)
    XCTAssertTrue(mockGPS.isSubscribed)

    let updatedFix = makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 4.0)
    mockGPS.simulateFix(updatedFix)
    try await waitFor { self.service.gpsAccuracy == Measurement(value: 4.0, unit: .meters) }

    service.stopSetupLocationUpdates()
    try await waitFor { !self.mockGPS.isSubscribed }
    XCTAssertEqual(setupToken?.invalidateCallCount, 1)
  }

  func testAnchorService_processLocationFix_emitsSingleStateUpdatePerFix() async throws {
    let debouncedService = try await makeDebouncedService(degradedAlertDelay: .milliseconds(500))
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    var emittedStates: [AnchorState] = []

    let observationTask = Task { @MainActor in
      for await state in debouncedService.stateUpdates {
        emittedStates.append(state)
      }
    }
    defer { observationTask.cancel() }

    try await waitFor { emittedStates.count == 1 }
    emittedStates.removeAll()

    // 1. Setup (.inactive) fix emits exactly once
    debouncedService.startSetupLocationUpdates()
    mockGPS.simulateFix(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 6.0))
    try await waitFor { emittedStates.count >= 1 }
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(emittedStates.count, 1)
    XCTAssertEqual(emittedStates.first?.gpsAccuracy, Measurement(value: 6.0, unit: .meters))
    emittedStates.removeAll()

    // 2. .droppedPendingPosition -> .dropped fulfillment emits exactly once with coordinate + distance populated
    debouncedService.drop(coordinate: nil, radius: Measurement(value: 50.0, unit: .meters))
    try await waitFor { emittedStates.count == 1 }
    emittedStates.removeAll()

    mockGPS.simulateFix(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 5.0))
    try await waitFor { emittedStates.count >= 1 }
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(emittedStates.count, 1)
    XCTAssertEqual(emittedStates.first?.status, .dropped)
    XCTAssertNotNil(emittedStates.first?.activeWatch?.coordinate)
    XCTAssertNotNil(emittedStates.first?.currentDistance)
    emittedStates.removeAll()

    // 3. .degraded fix in .armed emits exactly once (including updated isSensorDegraded flag)
    debouncedService.arm(coordinate: anchorCoord, radius: Measurement(value: 150.0, unit: .meters))
    try await waitFor { emittedStates.count == 1 }
    emittedStates.removeAll()

    mockGPS.locationContinuation?.yield(.degraded(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 65.0)))
    try await waitFor { emittedStates.count >= 1 }
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(emittedStates.count, 1)
    XCTAssertTrue(emittedStates.first?.isSensorDegraded == true)
    emittedStates.removeAll()

    // 4. .active fix triggering .dragging in .armed emits exactly once
    debouncedService.arm(coordinate: anchorCoord, radius: Measurement(value: 50.0, unit: .meters))
    try await waitFor { emittedStates.count == 1 }
    emittedStates.removeAll()

    let outsideCoord = CLLocationCoordinate2D(latitude: 45.002, longitude: -1.0)
    mockGPS.simulateFix(makeFix(coordinate: outsideCoord, horizontalAccuracyMeters: 5.0))
    try await waitFor { emittedStates.count >= 1 }
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(emittedStates.count, 1)
    XCTAssertEqual(emittedStates.first?.status, .dragging)
  }

  private func makeDebouncedService(degradedAlertDelay: Duration) async throws -> AnchorService {
    service.clear()
    try await waitFor { !self.mockGPS.isSubscribed }
    let debouncedService = AnchorService(
      positioningService: mockGPS,
      preferencesService: mockPrefs,
      notificationService: mockNotif,
      permissionService: mockPermission,
      backgroundMonitoringService: mockMonitoring,
      alarmAudioService: mockAudio,
      stateStore: mockStateStore,
      degradedAlertDelay: degradedAlertDelay
    )
    try await waitFor { self.mockGPS.isSubscribed }
    return debouncedService
  }

  private func makeFix(
    coordinate: CLLocationCoordinate2D,
    horizontalAccuracyMeters: Double
  ) -> NavigationFix {
    NavigationFix(
      coordinate: coordinate,
      horizontalAccuracy: Measurement(value: horizontalAccuracyMeters, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
  }

  func testAnchorService_degradedGPS_debouncesAndCancelsOnRecovery() async throws {
    let debouncedService = try await makeDebouncedService(degradedAlertDelay: .milliseconds(120))
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    debouncedService.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))

    mockGPS.locationContinuation?.yield(.degraded(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 65.0)))
    try await waitFor { debouncedService.isSensorDegraded }

    // Must NOT trigger immediate dragging/poorAccuracy alarm during 2s debounce window
    XCTAssertEqual(debouncedService.status, .armed)
    XCTAssertEqual(mockAudio.startSirenCallCount, 0)
    XCTAssertTrue(mockNotif.sentNotifications.isEmpty)

    // Recover before debounce expires
    mockGPS.locationContinuation?.yield(.active(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 5.0)))
    try await waitFor { !debouncedService.isSensorDegraded }
    try await Task.sleep(for: .milliseconds(180))

    XCTAssertEqual(debouncedService.status, .armed)
    XCTAssertEqual(mockAudio.startSirenCallCount, 0)
    XCTAssertTrue(mockNotif.sentNotifications.isEmpty)
  }

  func testAnchorService_degradedGPS_triggersPoorAccuracyAfterDelay_withoutDuplicateNotification() async throws {
    let debouncedService = try await makeDebouncedService(degradedAlertDelay: .milliseconds(50))
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    debouncedService.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))

    mockGPS.locationContinuation?.yield(.degraded(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 65.0)))
    try await waitFor { debouncedService.status == .dragging && self.mockNotif.sentNotifications.count == 1 }
    try await Task.sleep(for: .milliseconds(80))

    XCTAssertEqual(mockAudio.startSirenCallCount, 1)
    XCTAssertEqual(mockNotif.sentNotifications.count, 1)
    XCTAssertEqual(mockNotif.sentNotifications.first?.identifier, NotificationIntent.anchorDragging.rawValue)
    if case .poorAccuracy(let acc, let req) = debouncedService.triggerReason {
      XCTAssertEqual(acc.value, 65.0)
      XCTAssertEqual(req.value, 25.0)
    } else {
      XCTFail("Expected .poorAccuracy trigger reason, got \(String(describing: debouncedService.triggerReason))")
    }
  }

  func testAnchorService_degradedGPS_largeRadius_sendsMonitoringSuspendedAfterDelay() async throws {
    let debouncedService = try await makeDebouncedService(degradedAlertDelay: .milliseconds(50))
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    // Radius 150m -> requiredAccuracy 75m; 65m accuracy stays within requiredAccuracy
    debouncedService.arm(coordinate: anchorCoord, radius: Measurement(value: 150, unit: .meters))

    mockGPS.locationContinuation?.yield(.degraded(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 65.0)))
    try await waitFor { self.mockNotif.sentNotifications.count == 1 }

    XCTAssertEqual(debouncedService.status, .armed)
    XCTAssertEqual(mockAudio.startSirenCallCount, 0)
    XCTAssertEqual(mockNotif.sentNotifications.first?.identifier, NotificationIntent.anchorGPSDegraded.rawValue)
  }

  func testAnchorService_degradedGPS_cancelledByClear() async throws {
    let debouncedService = try await makeDebouncedService(degradedAlertDelay: .milliseconds(100))
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    debouncedService.arm(coordinate: anchorCoord, radius: Measurement(value: 150, unit: .meters))

    mockGPS.locationContinuation?.yield(.degraded(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 65.0)))
    try await waitFor { debouncedService.isSensorDegraded }

    debouncedService.clear()
    try await Task.sleep(for: .milliseconds(160))

    XCTAssertEqual(debouncedService.status, .inactive)
    XCTAssertTrue(mockNotif.sentNotifications.isEmpty)
  }

  func testAnchorService_degradedGPS_cancelsPendingTimerOnLost() async throws {
    let debouncedService = try await makeDebouncedService(degradedAlertDelay: .milliseconds(100))
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    debouncedService.arm(coordinate: anchorCoord, radius: Measurement(value: 150, unit: .meters))

    mockGPS.locationContinuation?.yield(.degraded(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 65.0)))
    try await waitFor { debouncedService.isSensorDegraded }

    struct GPSTestError: Error {}
    mockGPS.locationContinuation?.yield(.lost(GPSTestError()))
    try await waitFor { debouncedService.status == .dragging && self.mockNotif.sentNotifications.count == 1 }
    try await Task.sleep(for: .milliseconds(160))

    XCTAssertEqual(mockNotif.sentNotifications.count, 1)
    XCTAssertEqual(mockNotif.sentNotifications.first?.identifier, NotificationIntent.anchorDragging.rawValue)
    XCTAssertEqual(debouncedService.triggerReason, .gpsSignalLost)
  }

  func testAnchorService_degradedGPS_worseningAccuracyAfterMonitoringSuspended_triggersPoorAccuracyAlarm() async throws {
    let debouncedService = try await makeDebouncedService(degradedAlertDelay: .milliseconds(50))
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    // Radius 150m -> requiredAccuracy 75m
    debouncedService.arm(coordinate: anchorCoord, radius: Measurement(value: 150, unit: .meters))

    // 1. Enter .degraded with 65m accuracy (<= 75m requiredAccuracy) -> sends anchorGPSDegraded after 50ms
    mockGPS.locationContinuation?.yield(.degraded(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 65.0)))
    try await waitFor { self.mockNotif.sentNotifications.count == 1 }
    XCTAssertEqual(debouncedService.status, .armed)
    XCTAssertEqual(mockNotif.sentNotifications.first?.identifier, NotificationIntent.anchorGPSDegraded.rawValue)

    // 2. Subsequent .degraded fix worsens to 120m (> 75m requiredAccuracy) -> triggers .poorAccuracy immediately
    mockGPS.locationContinuation?.yield(.degraded(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 120.0)))
    try await waitFor { debouncedService.status == .dragging && self.mockNotif.sentNotifications.count == 2 }

    XCTAssertEqual(mockAudio.startSirenCallCount, 1)
    XCTAssertEqual(mockNotif.sentNotifications.last?.identifier, NotificationIntent.anchorDragging.rawValue)
    if case .poorAccuracy(let acc, let req) = debouncedService.triggerReason {
      XCTAssertEqual(acc.value, 120.0)
      XCTAssertEqual(req.value, 75.0)
    } else {
      XCTFail("Expected .poorAccuracy trigger reason, got \(String(describing: debouncedService.triggerReason))")
    }

    // 3. Degraded fix back <= 75m inside circle must NOT auto-resolve while still .degraded
    mockGPS.locationContinuation?.yield(.degraded(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 65.0)))
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertEqual(debouncedService.status, .dragging)
    XCTAssertTrue(debouncedService.isSensorDegraded)

    // 4. Reliable .active fix inside circle auto-resolves
    mockGPS.locationContinuation?.yield(.active(makeFix(coordinate: anchorCoord, horizontalAccuracyMeters: 5.0)))
    try await waitFor { debouncedService.status == .armed }
    XCTAssertFalse(debouncedService.isSensorDegraded)
  }
}


