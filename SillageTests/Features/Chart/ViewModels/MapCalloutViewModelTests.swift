//
//  MapCalloutViewModelTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
final class MapCalloutViewModelTests: XCTestCase {

  func testPresentAndDismissCallout() {
    let viewModel = MapCalloutViewModel()
    XCTAssertFalse(viewModel.isCalloutVisible)
    XCTAssertNil(viewModel.targetCoordinate)
    
    let targetCoord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)
    
    viewModel.presentCallout(coordinate: targetCoord, waypointID: "wp-123")
    
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, targetCoord.latitude)
    XCTAssertEqual(viewModel.targetCoordinate?.longitude, targetCoord.longitude)
    XCTAssertEqual(viewModel.targetWaypointID, "wp-123")
    
    viewModel.dismiss()
    
    XCTAssertFalse(viewModel.isCalloutVisible)
    XCTAssertNil(viewModel.targetWaypointID)
  }
  
  func testPointInfoPresentationLifecycle() {
    let viewModel = MapCalloutViewModel()
    XCTAssertFalse(viewModel.isPointInfoPresented)
    
    let targetCoord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)
    viewModel.presentCallout(coordinate: targetCoord)
    XCTAssertFalse(viewModel.isPointInfoPresented)
    
    viewModel.presentPointInfo()
    XCTAssertTrue(viewModel.isPointInfoPresented)
    
    viewModel.dismissPointInfo()
    XCTAssertFalse(viewModel.isPointInfoPresented)
    
    viewModel.presentPointInfo()
    XCTAssertTrue(viewModel.isPointInfoPresented)

    // Selecting a point or waypoint while point information is open keeps it presented
    viewModel.presentCallout(coordinate: targetCoord, waypointID: "wp-preserve")
    XCTAssertTrue(viewModel.isPointInfoPresented)

    viewModel.dismissPointInfo()
    XCTAssertFalse(viewModel.isPointInfoPresented)

    viewModel.presentPointInfo()
    XCTAssertTrue(viewModel.isPointInfoPresented)

    viewModel.dismiss()
    XCTAssertFalse(viewModel.isPointInfoPresented)
    XCTAssertFalse(viewModel.isCalloutVisible)
  }
  
  func testBearingAndDistanceCalculation() {
    let viewModel = MapCalloutViewModel()
    let vesselCoord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621) // Nantes
    let targetCoord = CLLocationCoordinate2D(latitude: 48.856614, longitude: 2.352222)   // Paris
    
    viewModel.presentCallout(coordinate: targetCoord)
    
    let bearing = viewModel.bearing(from: vesselCoord)
    let distance = viewModel.distance(from: vesselCoord)
    
    XCTAssertNotNil(bearing)
    XCTAssertNotNil(distance)
    
    if let bearing = bearing, let distance = distance {
      // Nantes to Paris is approximately 53° bearing and ~340 km (185 NM)
      XCTAssertGreaterThan(bearing.converted(to: .degrees).value, 40)
      XCTAssertLessThan(bearing.converted(to: .degrees).value, 70)
      
      XCTAssertGreaterThan(distance.converted(to: .meters).value, 300_000)
    }
  }
  
  func testShortDistanceAndCompassCardinalBearings() {
    let viewModel = MapCalloutViewModel()
    let vessel = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    
    // Target ~100m North
    let targetNorth = CLLocationCoordinate2D(latitude: 47.0009, longitude: -3.0)
    viewModel.presentCallout(coordinate: targetNorth)
    
    let bearingNorth = viewModel.bearing(from: vessel)
    let distanceNorth = viewModel.distance(from: vessel)
    
    XCTAssertNotNil(bearingNorth)
    XCTAssertNotNil(distanceNorth)
    
    if let brg = bearingNorth, let dist = distanceNorth {
      // True North is ~0° (or 360°)
      let degrees = brg.converted(to: .degrees).value
      XCTAssertTrue(degrees < 5.0 || degrees > 355.0, "Bearing to North should be ~0°, got \(degrees)°")
      
      // Short distance should be ~100 meters (< 185.2m / 0.1 NM threshold)
      XCTAssertGreaterThan(dist.converted(to: .meters).value, 50)
      XCTAssertLessThan(dist.converted(to: .meters).value, 200)
    }
    
    // Target East
    let targetEast = CLLocationCoordinate2D(latitude: 47.0, longitude: -2.99)
    viewModel.presentCallout(coordinate: targetEast)
    if let brgEast = viewModel.bearing(from: vessel) {
      let degrees = brgEast.converted(to: .degrees).value
      XCTAssertGreaterThan(degrees, 80)
      XCTAssertLessThan(degrees, 100)
    }
  }
  
  func testSameLocationBearingAndDistance() {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)
    
    viewModel.presentCallout(coordinate: coord)
    
    let distance = viewModel.distance(from: coord)
    XCTAssertNotNil(distance)
    if let distance = distance {
      XCTAssertEqual(distance.converted(to: .meters).value, 0.0, accuracy: 0.001)
    }
  }
  
  func testNilTelemetryHandling() {
    let viewModel = MapCalloutViewModel()
    
    // Without presenting callout (targetCoordinate is nil)
    XCTAssertNil(viewModel.bearing(from: CLLocationCoordinate2D(latitude: 47.0, longitude: -1.0)))
    XCTAssertNil(viewModel.distance(from: CLLocationCoordinate2D(latitude: 47.0, longitude: -1.0)))
    
    // With target set but nil vessel coordinate
    viewModel.presentCallout(coordinate: CLLocationCoordinate2D(latitude: 48.0, longitude: 2.0))
    XCTAssertNil(viewModel.bearing(from: nil))
    XCTAssertNil(viewModel.distance(from: nil))
  }
  
  func testTargetSelectionAndEnsureVisible() {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    
    // 1. Selecting an existing waypoint
    viewModel.presentCallout(coordinate: coord, waypointID: "existing-wp-1")
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.targetWaypointID, "existing-wp-1")
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, coord.latitude)
    
    // 2. Testing ensureVisible callback
    var reportedHeight: CGFloat = 0
    viewModel.onEnsureVisibleRequested = { height in
      reportedHeight = height
    }
    viewModel.ensureVisible(sheetHeight: 250.0)
    XCTAssertEqual(reportedHeight, 250.0)
    XCTAssertEqual(viewModel.lastSheetHeight, 250.0)
    
    // 3. Selecting empty map space
    viewModel.presentCallout(coordinate: coord, waypointID: nil)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertNil(viewModel.targetWaypointID)
  }
  
  func testDismissClearsCalloutState() {
    let viewModel = MapCalloutViewModel()
    viewModel.presentCallout(coordinate: CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0), waypointID: "target-1")
    
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.targetWaypointID, "target-1")
    
    viewModel.dismiss()
    
    XCTAssertFalse(viewModel.isCalloutVisible)
    XCTAssertNil(viewModel.targetWaypointID)
  }

  func testFormattedCoordinate() {
    let viewModel = MapCalloutViewModel()
    XCTAssertNil(viewModel.formattedCoordinate)
    
    let coord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)
    viewModel.presentCallout(coordinate: coord)
    
    let formatted = viewModel.formattedCoordinate
    XCTAssertNotNil(formatted)
    XCTAssertTrue(formatted?.contains("47°") == true)
  }

  func testUpdateTarget() {
    let viewModel = MapCalloutViewModel()
    let initialCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    viewModel.presentCallout(coordinate: initialCoord)

    let newCoord = CLLocationCoordinate2D(latitude: 47.05, longitude: -2.95)
    viewModel.updateTarget(coordinate: newCoord)

    XCTAssertEqual(viewModel.targetCoordinate?.latitude, newCoord.latitude)
    XCTAssertEqual(viewModel.targetCoordinate?.longitude, newCoord.longitude)

    viewModel.dismiss()
    XCTAssertFalse(viewModel.isCalloutVisible)
  }

  func testSheetHeightRetention() {
    let viewModel = MapCalloutViewModel()
    let initialCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    viewModel.presentCallout(coordinate: initialCoord)

    XCTAssertEqual(viewModel.lastSheetHeight, 220.0)
    viewModel.ensureVisible(sheetHeight: 285.0)
    XCTAssertEqual(viewModel.lastSheetHeight, 285.0)
  }

  func testBeginAimingWithNeedsCentering() {
    let viewModel = MapCalloutViewModel()
    let touchCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    let centerCoord = CLLocationCoordinate2D(latitude: 47.05, longitude: -2.95)

    XCTAssertFalse(viewModel.isCentering)
    XCTAssertNil(viewModel.aimingCoordinate)

    viewModel.beginAiming(at: touchCoord, needsCentering: true)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertTrue(viewModel.isCentering)
    XCTAssertEqual(viewModel.aimingCoordinate?.latitude, touchCoord.latitude)
    XCTAssertEqual(viewModel.aimingCoordinate?.longitude, touchCoord.longitude)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, touchCoord.latitude)

    viewModel.completeCentering(at: centerCoord)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertFalse(viewModel.isCentering)
    XCTAssertNil(viewModel.aimingCoordinate)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, centerCoord.latitude)
    XCTAssertEqual(viewModel.targetCoordinate?.longitude, centerCoord.longitude)

    viewModel.dismiss()
    XCTAssertFalse(viewModel.isCalloutVisible)
    XCTAssertFalse(viewModel.isCentering)
    XCTAssertNil(viewModel.aimingCoordinate)
  }

  func testBeginAimingWithoutNeedsCentering() {
    let viewModel = MapCalloutViewModel()
    let centerCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)

    viewModel.beginAiming(at: centerCoord, needsCentering: false)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertFalse(viewModel.isCentering)
    XCTAssertNil(viewModel.aimingCoordinate)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, centerCoord.latitude)
  }

  func testInterruptCenteringSnapsToCenter() {
    let viewModel = MapCalloutViewModel()
    let touchCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    let panCenterCoord = CLLocationCoordinate2D(latitude: 47.02, longitude: -2.98)

    viewModel.beginAiming(at: touchCoord, needsCentering: true)
    XCTAssertTrue(viewModel.isCentering)
    XCTAssertNotNil(viewModel.aimingCoordinate)

    viewModel.interruptCentering(at: panCenterCoord)
    XCTAssertFalse(viewModel.isCentering)
    XCTAssertNil(viewModel.aimingCoordinate)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, panCenterCoord.latitude)
    XCTAssertEqual(viewModel.targetCoordinate?.longitude, panCenterCoord.longitude)
  }

  func testPresentWaypointCalloutDoesNotSetCenteringOrAiming() {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)

    viewModel.presentWaypointCallout(coordinate: coord, waypointID: "wp-42")
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.targetWaypointID, "wp-42")
    XCTAssertFalse(viewModel.isCentering)
    XCTAssertNil(viewModel.aimingCoordinate)
  }

  func testEnsureVisibleInvokesCallbackWhenDialogArrives() {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    viewModel.presentCallout(coordinate: coord)
    
    var receivedSheetHeight: CGFloat? = nil
    viewModel.onEnsureVisibleRequested = { height in
      receivedSheetHeight = height
    }
    
    viewModel.ensureVisible(sheetHeight: 300.0)
    XCTAssertEqual(receivedSheetHeight, 300.0, "ensureVisible should trigger camera adjustment when the dialog arrives")
    XCTAssertEqual(viewModel.lastSheetHeight, 300.0)
  }

  func testAimingPreviewLifecycle() {
    let viewModel = MapCalloutViewModel()
    let touchCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    let dragCoord = CLLocationCoordinate2D(latitude: 47.01, longitude: -3.02)

    viewModel.startAimingPreview(at: touchCoord)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertFalse(viewModel.isCentering)
    XCTAssertEqual(viewModel.aimingCoordinate?.latitude, touchCoord.latitude)
    XCTAssertEqual(viewModel.aimingCoordinate?.longitude, touchCoord.longitude)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, touchCoord.latitude)

    viewModel.updateAimingPreview(at: dragCoord)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.aimingCoordinate?.latitude, dragCoord.latitude)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, dragCoord.latitude)

    viewModel.cancelAimingPreview()
    XCTAssertFalse(viewModel.isCalloutVisible)
    XCTAssertNil(viewModel.aimingCoordinate)
    XCTAssertNil(viewModel.targetCoordinate)
  }

  func testAimingPreviewThenBeginAiming() {
    let viewModel = MapCalloutViewModel()
    let touchCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)

    viewModel.startAimingPreview(at: touchCoord)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertNotNil(viewModel.aimingCoordinate)

    viewModel.beginAiming(at: touchCoord, needsCentering: true)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertTrue(viewModel.isCentering)
    XCTAssertEqual(viewModel.aimingCoordinate?.latitude, touchCoord.latitude)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, touchCoord.latitude)
  }

  func testAimingPreviewWhileCalloutAlreadyOpenPreservesVisibilityAndUpdatesTarget() {
    let viewModel = MapCalloutViewModel()
    let initialCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    let secondTouchCoord = CLLocationCoordinate2D(latitude: 47.05, longitude: -2.95)
    let secondDragCoord = CLLocationCoordinate2D(latitude: 47.06, longitude: -2.94)

    // First callout is already open
    viewModel.beginAiming(at: initialCoord, needsCentering: false)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertNil(viewModel.aimingCoordinate)

    // User long-presses elsewhere while callout is open
    viewModel.startAimingPreview(at: secondTouchCoord)
    XCTAssertTrue(viewModel.isCalloutVisible, "Callout must remain open during subsequent long press elsewhere")
    XCTAssertEqual(viewModel.aimingCoordinate?.latitude, secondTouchCoord.latitude)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, secondTouchCoord.latitude)

    // User drags finger
    viewModel.updateAimingPreview(at: secondDragCoord)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.aimingCoordinate?.latitude, secondDragCoord.latitude)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, secondDragCoord.latitude)

    // User releases finger
    viewModel.beginAiming(at: secondDragCoord, needsCentering: true)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertTrue(viewModel.isCentering)
    XCTAssertEqual(viewModel.aimingCoordinate?.latitude, secondDragCoord.latitude)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, secondDragCoord.latitude)
  }

  // MARK: - Point Information (Ephemeris & Magnetism) Tests

  func testPointInformationDefaultState() {
    let viewModel = MapCalloutViewModel()
    XCTAssertNil(viewModel.sunEphemeris)
    XCTAssertNil(viewModel.magneticDeclination)
    XCTAssertFalse(viewModel.isPointInfoLoading)
  }

  func testPresentPointInfoFetchesEphemerisAndDeclination() async {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621) // Nantes

    let calendar = Calendar(identifier: .gregorian)
    var components = DateComponents()
    components.year = 2026
    components.month = 1
    components.day = 1
    components.hour = 12
    components.minute = 0
    components.timeZone = TimeZone(identifier: "UTC")
    guard let fixedDate = calendar.date(from: components) else {
      XCTFail("Failed to construct deterministic test date")
      return
    }

    viewModel.presentCallout(coordinate: coord)
    viewModel.presentPointInfo(for: fixedDate)
    XCTAssertTrue(viewModel.isPointInfoPresented)

    let deadline = Date().addingTimeInterval(2.0)
    while viewModel.isPointInfoLoading && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }

    XCTAssertFalse(viewModel.isPointInfoLoading)
    XCTAssertNotNil(viewModel.sunEphemeris)
    if case let .cycle(sunrise, sunset) = viewModel.sunEphemeris?.daylight {
      XCTAssertLessThan(sunrise, sunset)
    } else {
      XCTFail("Expected .cycle daylight for Nantes, got \(String(describing: viewModel.sunEphemeris?.daylight))")
    }
    XCTAssertNotNil(viewModel.magneticDeclination)
    if let decl = viewModel.magneticDeclination {
      // Nantes (47.218° N, -1.554° W) in NOAA WMM-2025 at epoch 2026.0 has declination ~ +0.91° E.
      // Verified against official NOAA WMM2025 algorithm within tightened accuracy margin 0.05°.
      XCTAssertEqual(decl.converted(to: .degrees).value, 0.91, accuracy: 0.05)
    }
  }

  func testUpdateTargetRefetchesPointInformationWhenPointInfoPresented() async {
    let viewModel = MapCalloutViewModel()
    let initialCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    viewModel.presentCallout(coordinate: initialCoord)
    viewModel.presentPointInfo()

    var deadline = Date().addingTimeInterval(2.0)
    while viewModel.isPointInfoLoading && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertNotNil(viewModel.sunEphemeris)

    let initialDaylight = viewModel.sunEphemeris?.daylight
    let newCoord = CLLocationCoordinate2D(latitude: 12.0, longitude: 45.0)
    viewModel.updateTarget(coordinate: newCoord)

    deadline = Date().addingTimeInterval(2.0)
    while viewModel.sunEphemeris?.daylight == initialDaylight && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertNotNil(viewModel.sunEphemeris)
    XCTAssertNotNil(viewModel.magneticDeclination)
    XCTAssertNotEqual(viewModel.sunEphemeris?.daylight, initialDaylight)
  }

  func testDismissPointInfoClearsEphemerisAndDeclination() async {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    viewModel.presentCallout(coordinate: coord)
    viewModel.presentPointInfo()

    let deadline = Date().addingTimeInterval(2.0)
    while viewModel.isPointInfoLoading && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertNotNil(viewModel.sunEphemeris)
    XCTAssertNotNil(viewModel.magneticDeclination)

    viewModel.dismissPointInfo()
    XCTAssertFalse(viewModel.isPointInfoPresented)
    XCTAssertNil(viewModel.sunEphemeris)
    XCTAssertNil(viewModel.magneticDeclination)
    XCTAssertFalse(viewModel.isPointInfoLoading)
  }

  func testDismissClearsPointInformationState() async {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    viewModel.presentCallout(coordinate: coord)
    viewModel.presentPointInfo()

    let deadline = Date().addingTimeInterval(2.0)
    while viewModel.isPointInfoLoading && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertNotNil(viewModel.sunEphemeris)

    viewModel.dismiss()
    XCTAssertFalse(viewModel.isCalloutVisible)
    XCTAssertFalse(viewModel.isPointInfoPresented)
    XCTAssertNil(viewModel.sunEphemeris)
    XCTAssertNil(viewModel.magneticDeclination)
    XCTAssertFalse(viewModel.isPointInfoLoading)
  }

  func testLongPressSelectionWhilePointInfoOpenPreservesPresentation() async {
    let viewModel = MapCalloutViewModel()
    let initialCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    let secondCoord = CLLocationCoordinate2D(latitude: 47.05, longitude: -2.95)

    viewModel.presentCallout(coordinate: initialCoord)
    viewModel.presentPointInfo()
    XCTAssertTrue(viewModel.isPointInfoPresented)

    // Wait for initial point information to load
    var deadline = Date().addingTimeInterval(2.0)
    while viewModel.isPointInfoLoading && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertNotNil(viewModel.sunEphemeris)
    XCTAssertNotNil(viewModel.magneticDeclination)
    let initialDaylight = viewModel.sunEphemeris?.daylight
    let initialDeclination = viewModel.magneticDeclination?.converted(to: .degrees).value

    // User long presses elsewhere on the map: finger touch-down preserves existing point info to prevent skeleton flashing
    viewModel.startAimingPreview(at: secondCoord)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertTrue(viewModel.isPointInfoPresented, "Point info must remain open when user starts long-press selection")
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, secondCoord.latitude)
    XCTAssertNotNil(viewModel.sunEphemeris, "Existing ephemeris must be preserved to prevent skeleton flashing")
    XCTAssertNotNil(viewModel.magneticDeclination, "Existing declination must be preserved to prevent skeleton flashing")

    // User drags finger: existing values remain displayed to prevent skeleton flashing
    let dragCoord = CLLocationCoordinate2D(latitude: 25.0, longitude: -71.0)
    viewModel.updateAimingPreview(at: dragCoord)
    XCTAssertTrue(viewModel.isPointInfoPresented)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, dragCoord.latitude)
    XCTAssertNotNil(viewModel.sunEphemeris, "Existing ephemeris must remain preserved during aiming preview drag")
    XCTAssertNotNil(viewModel.magneticDeclination, "Existing declination must remain preserved during aiming preview drag")

    // User releases finger: needsCentering == true preserves values while flight is in progress
    viewModel.beginAiming(at: dragCoord, needsCentering: true)
    XCTAssertTrue(viewModel.isPointInfoPresented, "Point info must remain open after long press completes")
    XCTAssertTrue(viewModel.isCentering)
    XCTAssertNotNil(viewModel.sunEphemeris, "Point info remains preserved while centering camera flight is in progress")
    XCTAssertNotNil(viewModel.magneticDeclination, "Point info remains preserved while centering camera flight is in progress")

    // Centering flight completes: triggers actual fetch for the final target coordinate
    viewModel.completeCentering(at: dragCoord)
    XCTAssertTrue(viewModel.isPointInfoPresented, "Point info must remain open after camera centering completes")
    XCTAssertFalse(viewModel.isCentering)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, dragCoord.latitude)

    // Point information for the new coordinate must be recalculated and populated
    deadline = Date().addingTimeInterval(2.0)
    while viewModel.sunEphemeris?.daylight == initialDaylight && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertFalse(viewModel.isPointInfoLoading)
    XCTAssertNotNil(viewModel.sunEphemeris, "Ephemeris must be populated for new coordinate")
    XCTAssertNotNil(viewModel.magneticDeclination, "Magnetic declination must be populated for new coordinate")
    XCTAssertNotEqual(viewModel.sunEphemeris?.daylight, initialDaylight, "Ephemeris must reflect the new coordinate")
    XCTAssertNotEqual(viewModel.magneticDeclination?.converted(to: .degrees).value, initialDeclination, "Declination must reflect the new coordinate")
  }

  func testWaypointSelectionWhilePointInfoOpenPreservesPresentation() async {
    let viewModel = MapCalloutViewModel()
    let initialCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    let waypointCoord = CLLocationCoordinate2D(latitude: 43.2965, longitude: 5.3698) // Marseille

    viewModel.presentCallout(coordinate: initialCoord)
    viewModel.presentPointInfo()
    XCTAssertTrue(viewModel.isPointInfoPresented)

    // Wait for initial point information to load
    var deadline = Date().addingTimeInterval(2.0)
    while viewModel.isPointInfoLoading && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertNotNil(viewModel.sunEphemeris)
    XCTAssertNotNil(viewModel.magneticDeclination)
    let initialDaylight = viewModel.sunEphemeris?.daylight
    let initialDeclination = viewModel.magneticDeclination?.converted(to: .degrees).value

    // User long presses on an existing waypoint
    viewModel.presentWaypointCallout(coordinate: waypointCoord, waypointID: "wp-99")
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertTrue(viewModel.isPointInfoPresented, "Point info must remain open when user selects a waypoint")
    XCTAssertEqual(viewModel.targetWaypointID, "wp-99")
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, waypointCoord.latitude)

    // Point information for the waypoint must be recalculated and populated
    deadline = Date().addingTimeInterval(2.0)
    while viewModel.sunEphemeris?.daylight == initialDaylight && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertFalse(viewModel.isPointInfoLoading)
    XCTAssertNotNil(viewModel.sunEphemeris, "Ephemeris must be populated for waypoint")
    XCTAssertNotNil(viewModel.magneticDeclination, "Declination must be populated for waypoint")
    XCTAssertNotEqual(viewModel.sunEphemeris?.daylight, initialDaylight, "Ephemeris must reflect the waypoint's location")
    XCTAssertNotEqual(viewModel.magneticDeclination?.converted(to: .degrees).value, initialDeclination, "Declination must reflect the waypoint's location")
  }

  func testSelectionWhilePointInfoClosedDoesNotOpenPointInfo() {
    let viewModel = MapCalloutViewModel()
    let initialCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    let secondCoord = CLLocationCoordinate2D(latitude: 47.05, longitude: -2.95)

    viewModel.presentCallout(coordinate: initialCoord)
    XCTAssertFalse(viewModel.isPointInfoPresented)

    viewModel.startAimingPreview(at: secondCoord)
    XCTAssertFalse(viewModel.isPointInfoPresented)

    viewModel.beginAiming(at: secondCoord, needsCentering: false)
    XCTAssertFalse(viewModel.isPointInfoPresented)

    viewModel.presentWaypointCallout(coordinate: secondCoord, waypointID: "wp-100")
    XCTAssertFalse(viewModel.isPointInfoPresented)
  }

  func testMagneticDeclinationFooterText() {
    let viewModel = MapCalloutViewModel()

    XCTAssertNil(viewModel.magneticDeclinationFooterText)

    viewModel.magneticDeclination = Measurement<UnitAngle>(value: 1.2, unit: .degrees)
    XCTAssertEqual(
      viewModel.magneticDeclinationFooterText,
      "True to Magnetic: subtract 1.2° • Magnetic to True: add 1.2°"
    )

    viewModel.magneticDeclination = Measurement<UnitAngle>(value: -2.5, unit: .degrees)
    XCTAssertEqual(
      viewModel.magneticDeclinationFooterText,
      "True to Magnetic: add 2.5° • Magnetic to True: subtract 2.5°"
    )

    viewModel.magneticDeclination = Measurement<UnitAngle>(value: 0.0, unit: .degrees)
    XCTAssertEqual(
      viewModel.magneticDeclinationFooterText,
      "No significant variation between True and Magnetic bearings."
    )

    viewModel.magneticDeclination = Measurement<UnitAngle>(value: 0.04, unit: .degrees)
    XCTAssertEqual(
      viewModel.magneticDeclinationFooterText,
      "No significant variation between True and Magnetic bearings."
    )

    viewModel.magneticDeclination = nil
    XCTAssertNil(viewModel.magneticDeclinationFooterText)
  }
}
