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
  var locationContinuation: AsyncStream<PositioningState>.Continuation!
  var locationUpdates: AsyncStream<PositioningState>
  var currentDistanceFilter: Measurement<UnitLength> = Measurement(value: 10, unit: .meters)
  
  var currentAuthorizationStatus: CLAuthorizationStatus = .notDetermined
  
  var authContinuation: AsyncStream<CLAuthorizationStatus>.Continuation!
  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus>
  
  var lastKnownLocation: NavigationFix?
  
  init() {
    let (locStream, locCont) = AsyncStream.makeStream(of: PositioningState.self)
    self.locationUpdates = locStream
    self.locationContinuation = locCont
    
    let (authStream, authCont) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)
    self.authorizationStatusStream = authStream
    self.authContinuation = authCont
  }
  
  func requestAuthorization() {}
  private final class MockLocationUpdateToken: LocationUpdateToken {
    func invalidate() {}
  }
  func requestLocationUpdates() -> any LocationUpdateToken {
    return MockLocationUpdateToken()
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
    locationContinuation.yield(.active(fix))
  }
}

@MainActor
final class MockPreferencesService: PreferencesServiceProtocol {
  var savedChartSource: String?
  var savedGeoGarageLayerID: String?
  var geoGarageUsername: String?
  var savedLatitude: Double?
  var savedLongitude: Double?
  var savedZoom: Double?
  var savedDirection: Double?
  var savedTrackingMode: ChartTrackingMode = .northUp
  var gloveModeEnabled: Bool = false
  var hasAcceptedDisclaimer: Bool = false
  var isOpenSeaMapOverlayEnabled: Bool = false
  var isCOGVectorEnabled: Bool = false
  var cogVectorTimeHorizon: Measurement<UnitDuration> = Measurement(value: 0, unit: .seconds)
  var isCOGVectorTicksEnabled: Bool = false
  
  func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double) {}
  func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)? { return nil }
  
  var activeTrackSessionID: String?
  func saveActiveTrackSessionID(_ id: String) {}
  func clearActiveTrackSessionID() {}
  
  var goToWaypointID: String?
  var displayedTrackSessionID: String?
  
  var isBaroAlarmEnabled: Bool = false
  var baroAlarmSensitivity: BaroAlarmSensitivity = .medium
  var barometerOffset: Measurement<UnitPressure> = Measurement(value: 0, unit: .hectopascals)
  
  var savedAnchorWatch: AnchorWatch?
  var savedAnchorStatus: AnchorStatus = .inactive
  var savedAnchorRadius: Measurement<UnitLength> = Measurement(value: 25.0, unit: .meters)
}

@MainActor
final class MockNotificationService: NotificationService {
  var sentNotifications: [(title: String, body: String, identifier: String)] = []
  
  func sendNotification(title: String, body: String, identifier: String, delay: TimeInterval? = nil) async throws {
    sentNotifications.append((title, body, identifier))
  }
  
  func sendCriticalNotification(title: String, body: String, identifier: String) async {
    sentNotifications.append((title, body, identifier))
  }
  
  func clearAllNotifications() {}
  
  func cancelNotification(identifier: String) {}
  func checkIn(identifier: String, title: String, body: String, timeout: TimeInterval) async {}
  func cancelWatchdog(identifier: String) async {}
}

@MainActor
final class MockBackgroundMonitoringToken: BackgroundMonitoringToken {
  var isInvalidated = false
  func invalidate() { isInvalidated = true }
}

@MainActor
final class MockBackgroundMonitoringService: BackgroundMonitoringService {
  var requestedToken: MockBackgroundMonitoringToken?
  func startMonitoring(ownerIdentifier: String, distanceFilter: Measurement<UnitLength>, watchdog: WatchdogConfiguration?) -> any BackgroundMonitoringToken {
    let token = MockBackgroundMonitoringToken()
    requestedToken = token
    return token
  }
}

@MainActor
final class MockPermissionService: PermissionServiceProtocol {
    var locationStatus: PermissionStatus = .unknown
    var notificationStatus: PermissionStatus = .unknown
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
@MainActor
final class AnchorServiceTests: XCTestCase {
  
  var service: AnchorService!
  var mockGPS: MockPositioningService!
  var mockPrefs: MockPreferencesService!
  var mockNotif: MockNotificationService!
  var mockPermission: MockPermissionService!
  var mockMonitoring: MockBackgroundMonitoringService!
  
  override func setUp() {
    super.setUp()
    mockGPS = MockPositioningService()
    mockPrefs = MockPreferencesService()
    mockNotif = MockNotificationService()
    mockPermission = MockPermissionService()
    mockMonitoring = MockBackgroundMonitoringService()
    service = AnchorService(positioningService: mockGPS, preferencesService: mockPrefs, notificationService: mockNotif, permissionService: mockPermission, backgroundMonitoringService: mockMonitoring)
  }
  
  func testAnchorService_rejectsInvalidAccuracy_MinusOne() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    
    // Simulate a fix OUTSIDE the radius (e.g. 100m away) but with INVALID accuracy (-1)
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
    
    // Wait for the async task to process the fix
    try await Task.sleep(nanoseconds: 500_000_000) // 100ms
    
    // Status must still be .armed, NOT .dragging, because the fix was rejected
    XCTAssertEqual(service.status, .armed)
    XCTAssertEqual(mockNotif.sentNotifications.count, 0)
  }
  
  func testAnchorService_rejectsDegradedAccuracy_GreaterThanRadiusHalf() async throws {
    let anchorCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    service.arm(coordinate: anchorCoord, radius: Measurement(value: 50, unit: .meters))
    
    // Simulate a fix OUTSIDE the radius (e.g. 100m away) but with DEGRADED accuracy (> 25m)
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
    
    try await Task.sleep(nanoseconds: 500_000_000) // 100ms
    
    // Status must still be .armed, NOT .dragging
    XCTAssertEqual(service.status, .armed)
    XCTAssertEqual(mockNotif.sentNotifications.count, 0)
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
    
    try await Task.sleep(nanoseconds: 500_000_000) // 100ms
    
    // Status must change to dragging
    XCTAssertEqual(service.status, .dragging)
    XCTAssertEqual(mockNotif.sentNotifications.count, 1)
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
    try await Task.sleep(nanoseconds: 500_000_000)
    
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
    try await Task.sleep(nanoseconds: 500_000_000)
    
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
    try await Task.sleep(nanoseconds: 500_000_000)
    
    XCTAssertEqual(service.status, .armed)
    XCTAssertFalse(service.isMuted) // Mute flag should be reset
    
    // Go back outside
    mockGPS.simulateFix(validFix)
    try await Task.sleep(nanoseconds: 500_000_000)
    
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
    XCTAssertEqual(service.activeWatch?.coordinate.latitude, 45.0)
    
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
    XCTAssertEqual(service.activeWatch?.coordinate.latitude, 45.0)
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
    mockGPS.locationContinuation.yield(.active(fix))
    try await Task.sleep(nanoseconds: 500_000_000)
    
    // The distance MUST be calculated and updated
    XCTAssertNotNil(service.currentDistance)
    XCTAssertTrue(service.currentDistance!.value > 50.0)
    
    // The status MUST remain .dropped and NO notification should be sent
    XCTAssertEqual(service.status, .dropped)
    XCTAssertEqual(mockNotif.sentNotifications.count, 0)
  }
  
  func testAnchorService_initialization_resumesDroppedStateCorrectly() async throws {
    // Setup preferences to simulate an app launch with an existing "dropped" anchor
    let savedCoord = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    mockPrefs.savedAnchorWatch = AnchorWatch(coordinate: savedCoord, radius: Measurement(value: 60, unit: .meters))
    mockPrefs.savedAnchorStatus = .dropped
    
    // Re-initialize a new service with these mock preferences
    let newService = AnchorService(positioningService: mockGPS, preferencesService: mockPrefs, notificationService: mockNotif, permissionService: mockPermission, backgroundMonitoringService: mockMonitoring)
    
    XCTAssertEqual(newService.status, .dropped)
    XCTAssertNotNil(newService.activeWatch)
    XCTAssertEqual(newService.activeWatch?.radius.value, 60)
    
    // Must also have requested background location to compute live distance
    XCTAssertNotNil(mockMonitoring.requestedToken)
  }
}
