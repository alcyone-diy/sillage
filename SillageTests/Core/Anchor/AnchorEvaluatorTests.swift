//
//  AnchorEvaluatorTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
final class AnchorEvaluatorTests: XCTestCase {
  
  private let evaluator = AnchorEvaluator()
  private let centerCoord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)
  
  func testEvaluate_whenVesselWithinRadius_maintainsState() {
    let watch = AnchorWatch(
      coordinate: centerCoord,
      radius: Measurement(value: 50.0, unit: UnitLength.meters)
    )
    
    // Fix at the exact center with excellent accuracy
    let fix = NavigationFix(
      coordinate: centerCoord,
      horizontalAccuracy: Measurement(value: 3.0, unit: UnitLength.meters),
      courseOverGround: Measurement(value: 0.0, unit: UnitAngle.degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 0.2, unit: UnitSpeed.knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    let result = evaluator.evaluate(fix: fix, watch: watch, currentStatus: .armed)
    XCTAssertEqual(result, AnchorEvaluationResult.maintainState)
  }
  
  func testEvaluate_whenVesselExceedsRadius_triggersDistanceAlarm() {
    let watch = AnchorWatch(
      coordinate: centerCoord,
      radius: Measurement(value: 30.0, unit: UnitLength.meters)
    )
    
    // Projected position ~100m north
    guard let outsideCoord = centerCoord.greatCircleCoordinate(
      atDistance: Measurement(value: 100.0, unit: UnitLength.meters),
      bearing: Measurement(value: 0.0, unit: UnitAngle.degrees)
    ) else {
      XCTFail("Failed to project coordinate")
      return
    }
    
    let fix = NavigationFix(
      coordinate: outsideCoord,
      horizontalAccuracy: Measurement(value: 4.0, unit: UnitLength.meters),
      courseOverGround: Measurement(value: 0.0, unit: UnitAngle.degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 1.5, unit: UnitSpeed.knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    let result = evaluator.evaluate(fix: fix, watch: watch, currentStatus: .armed)
    
    if case .triggerAlarm(let reason) = result {
      if case .distanceExceeded(let distance, let radius) = reason {
        XCTAssertGreaterThan(distance, radius)
        XCTAssertEqual(radius, watch.radius)
      } else {
        XCTFail("Expected distanceExceeded reason, got \(reason)")
      }
    } else {
      XCTFail("Expected triggerAlarm result, got \(result)")
    }
  }
  
  func testEvaluate_whenVesselReturnsInsideCircle_autoResolvesAlarm() {
    let watch = AnchorWatch(
      coordinate: centerCoord,
      radius: Measurement(value: 50.0, unit: UnitLength.meters)
    )
    
    // Position 10m from anchor
    guard let insideCoord = centerCoord.greatCircleCoordinate(
      atDistance: Measurement(value: 10.0, unit: UnitLength.meters),
      bearing: Measurement(value: 90.0, unit: UnitAngle.degrees)
    ) else {
      XCTFail("Failed to project coordinate")
      return
    }
    
    let fix = NavigationFix(
      coordinate: insideCoord,
      horizontalAccuracy: Measurement(value: 3.0, unit: UnitLength.meters),
      courseOverGround: Measurement(value: 90.0, unit: UnitAngle.degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 0.5, unit: UnitSpeed.knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    let result = evaluator.evaluate(fix: fix, watch: watch, currentStatus: .dragging)
    
    if case .autoResolveAlarm(let reason) = result {
      if case .vesselReturnedInCircle(let distance) = reason {
        XCTAssertLessThanOrEqual(distance, watch.radius)
      }
    } else {
      XCTFail("Expected autoResolveAlarm result, got \(result)")
    }
  }
  
  func testEvaluate_whenAccuracyIsPoor_triggersPoorAccuracyAlarm() {
    let watch = AnchorWatch(
      coordinate: centerCoord,
      radius: Measurement(value: 30.0, unit: UnitLength.meters)
    )
    
    // Required accuracy is radius / 2 = 15m. Accuracy of 20m is degraded.
    let fix = NavigationFix(
      coordinate: centerCoord,
      horizontalAccuracy: Measurement(value: 20.0, unit: UnitLength.meters),
      courseOverGround: Measurement(value: 0.0, unit: UnitAngle.degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 0.1, unit: UnitSpeed.knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    let result = evaluator.evaluate(fix: fix, watch: watch, currentStatus: .armed)
    
    if case .triggerAlarm(let reason) = result {
      if case .poorAccuracy(let accuracy, let requiredAccuracy) = reason {
        XCTAssertEqual(accuracy, Measurement<UnitLength>(value: 20.0, unit: .meters))
        XCTAssertEqual(requiredAccuracy, Measurement<UnitLength>(value: 15.0, unit: .meters))
      } else {
        XCTFail("Expected poorAccuracy reason, got \(reason)")
      }
    } else {
      XCTFail("Expected triggerAlarm, got \(result)")
    }
  }
  
  func testEvaluate_whenAccuracyIsZeroOrNegative_triggersGPSLost() {
    let watch = AnchorWatch(
      coordinate: centerCoord,
      radius: Measurement(value: 50.0, unit: UnitLength.meters)
    )
    
    let fix = NavigationFix(
      coordinate: centerCoord,
      horizontalAccuracy: Measurement(value: 0.0, unit: UnitLength.meters),
      courseOverGround: Measurement(value: 0.0, unit: UnitAngle.degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 0.0, unit: UnitSpeed.knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    let result = evaluator.evaluate(fix: fix, watch: watch, currentStatus: .armed)
    XCTAssertEqual(result, AnchorEvaluationResult.triggerAlarm(reason: .gpsSignalLost))
  }
  
  func testEvaluate_whenWatchHasNoCoordinate_maintainsState() {
    let pendingWatch = AnchorWatch(
      coordinate: nil,
      radius: Measurement(value: 50.0, unit: UnitLength.meters)
    )
    
    let fix = NavigationFix(
      coordinate: centerCoord,
      horizontalAccuracy: Measurement(value: 5.0, unit: UnitLength.meters),
      courseOverGround: Measurement(value: 0.0, unit: UnitAngle.degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 0.0, unit: UnitSpeed.knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    
    let result = evaluator.evaluate(fix: fix, watch: pendingWatch, currentStatus: .droppedPendingPosition)
    XCTAssertEqual(result, AnchorEvaluationResult.maintainState)
  }
}
