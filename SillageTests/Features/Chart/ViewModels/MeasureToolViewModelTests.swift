//
//  MeasureToolViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
import SwiftUI
@testable import Sillage

@MainActor
final class MeasureToolViewModelTests: XCTestCase {

  func testInitialStateIsInactive() {
    let viewModel = MeasureToolViewModel()
    XCTAssertEqual(viewModel.state, .inactive)
    XCTAssertFalse(viewModel.isActive)
    XCTAssertNil(viewModel.startCoordinate)
    XCTAssertNil(viewModel.endCoordinate)
    XCTAssertNil(viewModel.distance)
    XCTAssertNil(viewModel.bearing)
    XCTAssertNil(viewModel.reciprocalBearing)
  }

  func testStartActivatesWithCoordinates() {
    let viewModel = MeasureToolViewModel()
    let start = CLLocationCoordinate2D(latitude: 43.5, longitude: 7.0)
    let end = CLLocationCoordinate2D(latitude: 43.6, longitude: 7.2)

    viewModel.start(at: start, initialEnd: end)

    XCTAssertTrue(viewModel.isActive)
    XCTAssertEqual(viewModel.startCoordinate?.latitude, 43.5)
    XCTAssertEqual(viewModel.startCoordinate?.longitude, 7.0)
    XCTAssertEqual(viewModel.endCoordinate?.latitude, 43.6)
    XCTAssertEqual(viewModel.endCoordinate?.longitude, 7.2)
    XCTAssertEqual(viewModel.activePin, .end)

    guard let dist = viewModel.distance else {
      XCTFail("Expected non-nil distance")
      return
    }
    XCTAssertGreaterThan(dist.converted(to: .nauticalMiles).value, 0.0)

    guard let brg = viewModel.bearing else {
      XCTFail("Expected non-nil bearing")
      return
    }
    XCTAssertGreaterThanOrEqual(brg.converted(to: .degrees).value, 0.0)
    XCTAssertLessThan(brg.converted(to: .degrees).value, 360.0)
  }

  func testIdenticalPointsEdgeCase() {
    let viewModel = MeasureToolViewModel()
    let point = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)

    viewModel.start(at: point, initialEnd: point)

    XCTAssertTrue(viewModel.isActive)
    // Distance must be strictly 0 meters
    XCTAssertEqual(viewModel.distance?.converted(to: .meters).value, 0.0)
    // Bearing and reciprocal bearing must be strictly nil for identical points
    XCTAssertNil(viewModel.bearing)
    XCTAssertNil(viewModel.reciprocalBearing)
  }

  func testEquatorCrossing() {
    let viewModel = MeasureToolViewModel()
    // From 5° North to 5° South along prime meridian
    let northPoint = CLLocationCoordinate2D(latitude: 5.0, longitude: 0.0)
    let southPoint = CLLocationCoordinate2D(latitude: -5.0, longitude: 0.0)

    viewModel.start(at: northPoint, initialEnd: southPoint)

    guard let distance = viewModel.distance else {
      XCTFail("Expected non-nil distance")
      return
    }
    // 10 degrees along meridian: 10 * 60 NM = ~600 NM
    let distNM = distance.converted(to: .nauticalMiles).value
    XCTAssertEqual(distNM, 600.0, accuracy: 5.0)

    // Heading due South should be 180 degrees
    guard let bearing = viewModel.bearing else {
      XCTFail("Expected non-nil bearing")
      return
    }
    XCTAssertEqual(bearing.converted(to: .degrees).value, 180.0, accuracy: 0.5)

    // Reciprocal bearing should be 0 / 360 degrees (due North)
    guard let reciprocal = viewModel.reciprocalBearing else {
      XCTFail("Expected non-nil reciprocal bearing")
      return
    }
    XCTAssertEqual(reciprocal.converted(to: .degrees).value, 0.0, accuracy: 0.5)
  }

  func testAntimeridianCrossing() {
    let viewModel = MeasureToolViewModel()
    // From 179.0°E to -179.0° (179°W) at equator
    let westSide = CLLocationCoordinate2D(latitude: 0.0, longitude: 179.0)
    let eastSide = CLLocationCoordinate2D(latitude: 0.0, longitude: -179.0)

    viewModel.start(at: westSide, initialEnd: eastSide)

    guard let distance = viewModel.distance else {
      XCTFail("Expected non-nil distance")
      return
    }
    // Distance across 2 degrees at equator is ~120 NM (not ~21,480 NM the long way around)
    let distNM = distance.converted(to: .nauticalMiles).value
    XCTAssertEqual(distNM, 120.0, accuracy: 2.0)

    // Direction from 179°E to 179°W across antimeridian is due East (90 degrees)
    guard let bearing = viewModel.bearing else {
      XCTFail("Expected non-nil bearing")
      return
    }
    XCTAssertEqual(bearing.converted(to: .degrees).value, 90.0, accuracy: 0.5)

    // Reciprocal bearing should be due West (270 degrees)
    guard let reciprocal = viewModel.reciprocalBearing else {
      XCTFail("Expected non-nil reciprocal bearing")
      return
    }
    XCTAssertEqual(reciprocal.converted(to: .degrees).value, 270.0, accuracy: 0.5)
  }

  func testPinUpdatingAndMapTapHandling() {
    let viewModel = MeasureToolViewModel()
    let initialStart = CLLocationCoordinate2D(latitude: 10.0, longitude: 10.0)
    let initialEnd = CLLocationCoordinate2D(latitude: 10.0, longitude: 11.0)

    viewModel.start(at: initialStart, initialEnd: initialEnd)

    // Default active pin is .end
    XCTAssertEqual(viewModel.activePin, .end)

    // Single tap with active pin = .end MUST NOT move end pin
    let newEnd = CLLocationCoordinate2D(latitude: 10.0, longitude: 12.0)
    viewModel.handleMapTap(at: newEnd)
    XCTAssertEqual(viewModel.endCoordinate?.longitude, 11.0)
    XCTAssertEqual(viewModel.startCoordinate?.longitude, 10.0)

    // Long press with active pin = .end MUST move end pin
    viewModel.handleMapLongPress(at: newEnd)
    XCTAssertEqual(viewModel.endCoordinate?.longitude, 12.0)
    XCTAssertEqual(viewModel.startCoordinate?.longitude, 10.0)

    // Switch active pin to .start
    viewModel.activePin = .start
    let newStart = CLLocationCoordinate2D(latitude: 10.0, longitude: 9.0)

    // Single tap with active pin = .start MUST NOT move start pin
    viewModel.handleMapTap(at: newStart)
    XCTAssertEqual(viewModel.startCoordinate?.longitude, 10.0)
    XCTAssertEqual(viewModel.endCoordinate?.longitude, 12.0)

    // Long press with active pin = .start MUST move start pin
    viewModel.handleMapLongPress(at: newStart)
    XCTAssertEqual(viewModel.startCoordinate?.longitude, 9.0)
    XCTAssertEqual(viewModel.endCoordinate?.longitude, 12.0)

    // Direct update methods
    viewModel.updateStart(to: CLLocationCoordinate2D(latitude: 11.0, longitude: 9.0))
    XCTAssertEqual(viewModel.startCoordinate?.latitude, 11.0)

    viewModel.updateEnd(to: CLLocationCoordinate2D(latitude: 11.0, longitude: 15.0))
    XCTAssertEqual(viewModel.endCoordinate?.longitude, 15.0)
  }

  func testStopResetsStateToInactive() {
    let viewModel = MeasureToolViewModel()
    viewModel.start(
      at: CLLocationCoordinate2D(latitude: 10.0, longitude: 10.0),
      initialEnd: CLLocationCoordinate2D(latitude: 11.0, longitude: 11.0)
    )
    XCTAssertTrue(viewModel.isActive)

    viewModel.stop()

    XCTAssertFalse(viewModel.isActive)
    XCTAssertEqual(viewModel.state, .inactive)
    XCTAssertNil(viewModel.startCoordinate)
    XCTAssertNil(viewModel.endCoordinate)
    XCTAssertNil(viewModel.distance)
    XCTAssertNil(viewModel.bearing)
  }

  func testMarineMapPinShapePathCreation() {
    XCTAssertEqual(MarineMapPinShape.defaultWidth, 36.0)
    XCTAssertEqual(MarineMapPinShape.defaultHeight, 62.0)
    XCTAssertEqual(MarineMapPinShape.needleToHeadCenterOffset, 44.0)

    // 1. Test .up direction (default, needle points up to tip at minY)
    let pinUp = MarineMapPinShape(direction: .up)
    let rectUp = CGRect(x: 0, y: 0, width: 36, height: 62)
    let pathUp = pinUp.path(in: rectUp)

    XCTAssertFalse(pathUp.isEmpty)
    XCTAssertGreaterThan(pathUp.boundingRect.width, 32.0)
    XCTAssertGreaterThan(pathUp.boundingRect.height, 58.0)

    // Needle tip at top center
    XCTAssertTrue(pathUp.contains(CGPoint(x: 18.0, y: 2.0)))
    // Circular head at bottom center (center at y = 44)
    XCTAssertTrue(pathUp.contains(CGPoint(x: 18.0, y: 44.0)))

    // 2. Test .down direction (needle points down to tip at maxY)
    let pinDown = MarineMapPinShape(direction: .down)
    let rectDown = CGRect(x: 0, y: 0, width: 36, height: 62)
    let pathDown = pinDown.path(in: rectDown)

    XCTAssertFalse(pathDown.isEmpty)
    XCTAssertGreaterThan(pathDown.boundingRect.width, 32.0)
    XCTAssertGreaterThan(pathDown.boundingRect.height, 58.0)

    // Needle tip at bottom center
    XCTAssertTrue(pathDown.contains(CGPoint(x: 18.0, y: 60.0)))
    // Circular head at top center (center at y = 18)
    XCTAssertTrue(pathDown.contains(CGPoint(x: 18.0, y: 18.0)))
  }
}
