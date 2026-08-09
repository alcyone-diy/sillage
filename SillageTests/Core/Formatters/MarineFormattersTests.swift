//
//  MarineFormattersTests.swift
//  SillageTests
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

final class MarineFormattersTests: XCTestCase {
  func testShortDistanceThresholdValue() {
    XCTAssertEqual(MarineFormatters.shortDistanceThreshold.converted(to: .meters).value, 185.2, accuracy: 0.001)
  }

  func testMarineContextualDistanceFormattedForShortDistance() {
    let dist = Measurement<UnitLength>(value: 50, unit: .meters)
    let formatted = dist.marineContextualDistanceFormatted

    // Distance below threshold should format in system short unit (e.g. m or ft), not nautical miles (NM)
    XCTAssertFalse(formatted.contains("NM"))
  }

  func testMarineContextualDistanceFormattedForLongDistance() {
    let dist = Measurement<UnitLength>(value: 500, unit: .meters)
    let formatted = dist.marineContextualDistanceFormatted
    // 500 meters is ~0.27 nautical miles
    let expected = dist.converted(to: .nauticalMiles).formatted(
      .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2)))
    )
    XCTAssertEqual(formatted, expected)
  }
}
