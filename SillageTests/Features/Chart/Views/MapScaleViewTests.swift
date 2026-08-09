//
//  MapScaleViewTests.swift
//  SillageTests
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

final class MapScaleViewTests: XCTestCase {
  func testShortDistanceUnitAdaptsToMeasurementSystem() {
    let isMetric = Locale.current.measurementSystem == .metric
    let targetUnit: UnitLength = isMetric ? .meters : .feet

    let maxDistanceMeters = Measurement<UnitLength>(value: 30.0, unit: .meters)
    XCTAssertLessThan(maxDistanceMeters, MarineFormatters.shortDistanceThreshold)

    let maxDistInTargetUnit = maxDistanceMeters.converted(to: targetUnit).value
    XCTAssertGreaterThan(maxDistInTargetUnit, 0)
    
    if isMetric {
      XCTAssertEqual(targetUnit, .meters)
    } else {
      XCTAssertEqual(targetUnit, .feet)
    }
  }
}
