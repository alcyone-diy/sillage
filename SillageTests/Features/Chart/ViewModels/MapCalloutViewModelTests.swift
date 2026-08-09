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
    
    let screenPoint = CGPoint(x: 150, y: 300)
    let targetCoord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)
    
    viewModel.presentCallout(at: screenPoint, coordinate: targetCoord, waypointID: "wp-123")
    
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.screenPoint, screenPoint)
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
    
    viewModel.presentCallout(at: CGPoint(x: 100, y: 100), coordinate: targetCoord)
    
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
    viewModel.presentCallout(at: .zero, coordinate: targetNorth)
    
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
    viewModel.presentCallout(at: .zero, coordinate: targetEast)
    if let brgEast = viewModel.bearing(from: vessel) {
      let degrees = brgEast.converted(to: .degrees).value
      XCTAssertGreaterThan(degrees, 80)
      XCTAssertLessThan(degrees, 100)
    }
  }
  
  func testSameLocationBearingAndDistance() {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)
    
    viewModel.presentCallout(at: .zero, coordinate: coord)
    
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
    viewModel.presentCallout(at: .zero, coordinate: CLLocationCoordinate2D(latitude: 48.0, longitude: 2.0))
    XCTAssertNil(viewModel.bearing(from: nil))
    XCTAssertNil(viewModel.distance(from: nil))
  }
  
  func testHybridAnchorModeSelection() {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    
    // 1. Long pressing an existing waypoint sets fixedGeographic mode (targetWaypointID != nil)
    viewModel.presentCallout(at: CGPoint(x: 100, y: 200), coordinate: coord, waypointID: "existing-wp-1")
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.targetWaypointID, "existing-wp-1")
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, coord.latitude)
    
    // 2. Long pressing empty map space sets fixedScreen mode (targetWaypointID == nil)
    viewModel.presentCallout(at: CGPoint(x: 200, y: 400), coordinate: coord, waypointID: nil)
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertNil(viewModel.targetWaypointID)
    XCTAssertEqual(viewModel.screenPoint, CGPoint(x: 200, y: 400))
  }
  
  func testDismissClearsCalloutState() {
    let viewModel = MapCalloutViewModel()
    viewModel.presentCallout(at: CGPoint(x: 50, y: 50), coordinate: CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0), waypointID: "target-1")
    
    XCTAssertTrue(viewModel.isCalloutVisible)
    XCTAssertEqual(viewModel.targetWaypointID, "target-1")
    
    viewModel.dismiss()
    
    XCTAssertFalse(viewModel.isCalloutVisible)
    XCTAssertNil(viewModel.targetWaypointID)
  }

  func testCoordinate2DDistanceToAndThresholdEvaluation() {
    let p1 = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    // ~111 meters North
    let p2 = CLLocationCoordinate2D(latitude: 47.001, longitude: -3.0)

    let dist = p1.distance(to: p2)
    XCTAssertGreaterThan(dist.converted(to: .meters).value, 100.0)
    XCTAssertLessThan(dist.converted(to: .meters).value, 120.0)

    // Verify distance to self is 0 meters
    XCTAssertEqual(p1.distance(to: p1).converted(to: .meters).value, 0.0, accuracy: 0.001)
  }
}
