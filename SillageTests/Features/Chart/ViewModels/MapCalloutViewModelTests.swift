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
import MapLibre
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
  
  func testTargetSelectionAndEnsureVisible() {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    
    // 1. Long pressing an existing waypoint
    viewModel.presentCallout(at: CGPoint(x: 100, y: 200), coordinate: coord, waypointID: "existing-wp-1")
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
    
    // 3. Long pressing empty map space
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

  func testFormattedCoordinate() {
    let viewModel = MapCalloutViewModel()
    XCTAssertNil(viewModel.formattedCoordinate)
    
    let coord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)
    viewModel.presentCallout(at: .zero, coordinate: coord)
    
    let formatted = viewModel.formattedCoordinate
    XCTAssertNotNil(formatted)
    XCTAssertTrue(formatted?.contains("47°") == true)
  }

  func testMapPanDoesNotDismissCallout() {
    let viewModel = MapCalloutViewModel()
    let coord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)
    viewModel.presentCallout(at: CGPoint(x: 200, y: 400), coordinate: coord)
    XCTAssertTrue(viewModel.isCalloutVisible)

    // Simulate an offscreen projection: MLNMapView converts offscreen coordinate
    let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
    // Call updateScreenPositionImmediately with mapView where the coordinate is off-screen
    viewModel.updateScreenPositionImmediately(from: mapView)

    // Callout must remain visible even if the coordinate projected outside map bounds
    XCTAssertTrue(viewModel.isCalloutVisible)
  }

  func testUpdateTargetDuringDrag() {
    let viewModel = MapCalloutViewModel()
    let initialCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    viewModel.presentCallout(at: CGPoint(x: 100, y: 100), coordinate: initialCoord)
    XCTAssertFalse(viewModel.isDraggingPin)

    viewModel.beginDragging()
    XCTAssertTrue(viewModel.isDraggingPin)

    let newScreenPoint = CGPoint(x: 150, y: 220)
    let newCoord = CLLocationCoordinate2D(latitude: 47.05, longitude: -2.95)

    viewModel.updateTarget(screenPoint: newScreenPoint, coordinate: newCoord)

    XCTAssertTrue(viewModel.isDraggingPin)
    XCTAssertEqual(viewModel.screenPoint, newScreenPoint)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, newCoord.latitude)
    XCTAssertEqual(viewModel.targetCoordinate?.longitude, newCoord.longitude)

    viewModel.endDragging()
    XCTAssertFalse(viewModel.isDraggingPin)

    viewModel.dismiss()
    XCTAssertFalse(viewModel.isDraggingPin)
    XCTAssertFalse(viewModel.isCalloutVisible)
  }

  func testProjectionIgnoredDuringDrag() {
    let viewModel = MapCalloutViewModel()
    let initialCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    viewModel.presentCallout(at: CGPoint(x: 100, y: 100), coordinate: initialCoord)

    viewModel.beginDragging()
    let draggedScreenPoint = CGPoint(x: 150, y: 220)
    let draggedCoord = CLLocationCoordinate2D(latitude: 47.05, longitude: -2.95)
    viewModel.updateTarget(screenPoint: draggedScreenPoint, coordinate: draggedCoord)

    let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
    // Throttled or immediate update shouldn't overwrite the drag position while dragging
    viewModel.throttledUpdateScreenPosition(from: mapView)
    XCTAssertEqual(viewModel.screenPoint, draggedScreenPoint)

    viewModel.updateScreenPositionImmediately(from: mapView)
    XCTAssertEqual(viewModel.screenPoint, draggedScreenPoint)
  }

  func testCompleteDragLifecycleAndProjectionResumption() {
    let viewModel = MapCalloutViewModel()
    let initialCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    viewModel.presentCallout(at: CGPoint(x: 100, y: 100), coordinate: initialCoord)
    XCTAssertFalse(viewModel.isDraggingPin)

    // 1. Begin drag
    viewModel.beginDragging()
    XCTAssertTrue(viewModel.isDraggingPin)

    // 2. Projections are completely ignored during drag
    let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
    let intermediateScreenPoint = CGPoint(x: 180, y: 240)
    let intermediateCoord = CLLocationCoordinate2D(latitude: 47.02, longitude: -2.98)
    viewModel.updateTarget(screenPoint: intermediateScreenPoint, coordinate: intermediateCoord)
    XCTAssertEqual(viewModel.screenPoint, intermediateScreenPoint)
    XCTAssertEqual(viewModel.targetCoordinate?.latitude, intermediateCoord.latitude)

    viewModel.throttledUpdateScreenPosition(from: mapView)
    XCTAssertEqual(viewModel.screenPoint, intermediateScreenPoint)
    viewModel.updateScreenPositionImmediately(from: mapView)
    XCTAssertEqual(viewModel.screenPoint, intermediateScreenPoint)

    // 3. End drag
    viewModel.endDragging()
    XCTAssertFalse(viewModel.isDraggingPin)

    // 4. Projections resume normally after drag session ends
    viewModel.updateScreenPositionImmediately(from: mapView)
    let projectedPoint = mapView.convert(intermediateCoord, toPointTo: mapView)
    XCTAssertEqual(viewModel.screenPoint.x, projectedPoint.x, accuracy: 0.5)
    XCTAssertEqual(viewModel.screenPoint.y, projectedPoint.y, accuracy: 0.5)

    // 5. Verify lastSheetHeight retention
    XCTAssertEqual(viewModel.lastSheetHeight, 220.0)
    viewModel.ensureVisible(sheetHeight: 285.0)
    XCTAssertEqual(viewModel.lastSheetHeight, 285.0)
  }
}
