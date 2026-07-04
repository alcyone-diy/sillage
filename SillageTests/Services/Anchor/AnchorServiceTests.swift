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
  var locationContinuation: AsyncStream<NavigationFix>.Continuation!
  var locationUpdates: AsyncStream<NavigationFix>
  
  var authContinuation: AsyncStream<CLAuthorizationStatus>.Continuation!
  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus>
  
  init() {
    let (locStream, locCont) = AsyncStream.makeStream(of: NavigationFix.self)
    self.locationUpdates = locStream
    self.locationContinuation = locCont
    
    let (authStream, authCont) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)
    self.authorizationStatusStream = authStream
    self.authContinuation = authCont
  }
  
  func requestAuthorization() {}
  func startUpdatingLocation() {}
  func stopUpdatingLocation() {}
  
  var requestedToken: MockBackgroundLocationToken?
  func requestBackgroundLocation() -> any BackgroundLocationToken {
    let token = MockBackgroundLocationToken()
    requestedToken = token
    return token
  }
  
  func simulateFix(_ fix: NavigationFix) {
    locationContinuation.yield(fix)
  }
}

@MainActor
final class MockPreferencesService: PreferencesServiceProtocol {
  var savedChartSource: String?
  var savedGeoGarageLayerID: String?
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
}

@MainActor
final class MockNotificationService: NotificationService {
  var notificationsSent = 0
  
  func requestAuthorization() async throws -> Bool { return true }
  
  func sendNotification(title: String, body: String, identifier: String) async {
    notificationsSent += 1
  }
  
  func requestCriticalAuthorization() async throws -> Bool { return true }
  
  func sendCriticalNotification(title: String, body: String, identifier: String) async {
    notificationsSent += 1
  }
  
  func clearDeliveredNotifications() {}
}
@MainActor
final class AnchorServiceTests: XCTestCase {
  
  var service: AnchorService!
  var mockGPS: MockPositioningService!
  var mockPrefs: MockPreferencesService!
  var mockNotif: MockNotificationService!
  
  override func setUp() {
    super.setUp()
    mockGPS = MockPositioningService()
    mockPrefs = MockPreferencesService()
    mockNotif = MockNotificationService()
    service = AnchorService(positioningService: mockGPS, preferencesService: mockPrefs, notificationService: mockNotif)
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
      courseState: .invalid,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(badFix)
    
    // Wait for the async task to process the fix
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    // Status must still be .armed, NOT .dragging, because the fix was rejected
    XCTAssertEqual(service.status, .armed)
    XCTAssertEqual(mockNotif.notificationsSent, 0)
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
      courseState: .invalid,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(degradedFix)
    
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    // Status must still be .armed, NOT .dragging
    XCTAssertEqual(service.status, .armed)
    XCTAssertEqual(mockNotif.notificationsSent, 0)
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
      courseState: .invalid,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(validFix)
    
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    // Status must change to dragging
    XCTAssertEqual(service.status, .dragging)
    XCTAssertEqual(mockNotif.notificationsSent, 1)
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
      courseState: .invalid,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(validFix)
    try await Task.sleep(nanoseconds: 100_000_000)
    
    XCTAssertEqual(service.status, .dragging)
    XCTAssertEqual(mockNotif.notificationsSent, 1)
    
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
      courseState: .invalid,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(furtherFix)
    try await Task.sleep(nanoseconds: 100_000_000)
    
    // Notification shouldn't trigger again because it is muted (and already dragging)
    XCTAssertEqual(service.status, .dragging)
    XCTAssertEqual(mockNotif.notificationsSent, 1)
    
    // Return inside radius
    let returnFixCoord = CLLocationCoordinate2D(latitude: 45.0001, longitude: -1.0) // ~11m away
    let returnFix = NavigationFix(
      coordinate: returnFixCoord,
      horizontalAccuracy: Measurement(value: 10.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      courseState: .invalid,
      timestamp: Date()
    )
    
    mockGPS.simulateFix(returnFix)
    try await Task.sleep(nanoseconds: 100_000_000)
    
    XCTAssertEqual(service.status, .armed)
    XCTAssertFalse(service.isMuted) // Mute flag should be reset
    
    // Go back outside
    mockGPS.simulateFix(validFix)
    try await Task.sleep(nanoseconds: 100_000_000)
    
    XCTAssertEqual(service.status, .dragging)
    XCTAssertEqual(mockNotif.notificationsSent, 2) // Notification triggers again!
  }
}
