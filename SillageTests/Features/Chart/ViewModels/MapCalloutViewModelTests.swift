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

  func testPresentCalloutWithZeroOffsetDoesNotSetCentering() {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)

    viewModel.presentCallout(coordinate: coord, waypointID: nil, initialOffset: .zero)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.crosshairOffset, .zero)
    XCTAssertFalse(viewModel.isCentering, "isCentering should be false when initialOffset is zero")
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

  func testCrosshairOffsetAndCenteringLifecycle() {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    let initialOffset = CGSize(width: 50.0, height: -120.0)

    XCTAssertEqual(viewModel.crosshairOffset, .zero)
    XCTAssertFalse(viewModel.isCentering)

    viewModel.presentCallout(coordinate: coord, waypointID: nil, initialOffset: initialOffset)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.crosshairOffset, initialOffset)
    XCTAssertTrue(viewModel.isCentering)

    viewModel.centerCrosshair()
    XCTAssertEqual(viewModel.crosshairOffset, .zero)

    viewModel.dismiss()
    XCTAssertFalse(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.crosshairOffset, .zero)
    XCTAssertFalse(viewModel.isCentering)
  }
}
