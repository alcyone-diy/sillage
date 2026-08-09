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
    let formatted = dist.marineContextualDistanceFormatted()

    // Distance below threshold should format in system short unit (e.g. m or ft), not nautical miles (NM)
    XCTAssertFalse(formatted.contains("NM"))
  }

  func testSubMeterDistanceDoesNotScaleToCentimetersOrInches() {
    // Very short distance below 1 meter (0.5 meters / 50cm)
    let dist = Measurement<UnitLength>(value: 0.5, unit: .meters)
    let formatted = dist.marineContextualDistanceFormatted()

    // Must strictly remain in meters or feet, forbidding sub-unit scaling (cm or in)
    XCTAssertFalse(formatted.contains("cm"))
    XCTAssertFalse(formatted.contains("in"))

    let isMetric = Locale.current.measurementSystem == .metric
    let expectedUnitSymbol = isMetric ? "m" : "ft"
    XCTAssertTrue(formatted.contains(expectedUnitSymbol))
  }

  func testMarineContextualDistanceFormattedForLongDistance() {
    let dist = Measurement<UnitLength>(value: 500, unit: .meters)
    let formatted = dist.marineContextualDistanceFormatted()
    // 500 meters is ~0.27 nautical miles
    let expected = dist.converted(to: .nauticalMiles).formatted(
      .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2)))
    )
    XCTAssertEqual(formatted, expected)
  }

  func testMarineAnchorDistanceFormatted_MetricLocale() {
    let distance = Measurement<UnitLength>(value: 50.0, unit: .meters)
    let metricLocale = Locale(components: .init(languageCode: .french, script: nil, languageRegion: .france))
    
    let result = distance.marineAnchorDistanceFormatted(locale: metricLocale)
    
    // In metric locales, 50m formats as meters ("50 m")
    XCTAssertTrue(result.contains("50"), "Expected formatted result to contain '50', got: \(result)")
    XCTAssertTrue(result.contains("m"), "Expected formatted result to contain 'm', got: \(result)")
  }

  func testMarineAnchorDistanceFormatted_USLocale() {
    let distance = Measurement<UnitLength>(value: 50.0, unit: .meters)
    let usLocale = Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates))
    
    let result = distance.marineAnchorDistanceFormatted(locale: usLocale)
    
    // 50m is approx 164 feet, formatted as feet ("164 ft")
    XCTAssertTrue(result.contains("164"), "Expected formatted result to contain '164', got: \(result)")
    XCTAssertTrue(result.contains("ft"), "Expected formatted result to contain 'ft', got: \(result)")
  }

  func testMarineAnchorDistanceFormatted_UKLocale() {
    let distance = Measurement<UnitLength>(value: 50.0, unit: .meters)
    let ukLocale = Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedKingdom))
    
    let result = distance.marineAnchorDistanceFormatted(locale: ukLocale)
    
    // UK locale uses feet for short anchor distances ("164 ft")
    XCTAssertTrue(result.contains("164"), "Expected formatted result to contain '164', got: \(result)")
    XCTAssertTrue(result.contains("ft"), "Expected formatted result to contain 'ft', got: \(result)")
  }
}
