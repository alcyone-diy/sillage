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
    let enUSLocale = Locale(identifier: "en_US_POSIX")
    let dist = Measurement<UnitLength>(value: 500, unit: .meters)
    let formatted = dist.marineContextualDistanceFormatted(locale: enUSLocale)
    let expected = dist.converted(to: .marineNauticalMiles).formatted(
      .measurement(
        width: .abbreviated,
        usage: .asProvided,
        numberFormatStyle: .number.precision(.fractionLength(2))
      ).locale(enUSLocale)
    )
    XCTAssertEqual(formatted, expected)
    XCTAssertEqual(formatted, "0.27 NM")
  }

  func testMarineNauticalMilesFormattedPrecision_EnUSLocale() {
    let enUSLocale = Locale(identifier: "en_US_POSIX")

    let smallDist = Measurement<UnitLength>(value: 5.234, unit: .marineNauticalMiles)
    XCTAssertEqual(smallDist.marineNauticalMilesFormatted(locale: enUSLocale), "5.23 NM")

    let mediumDist = Measurement<UnitLength>(value: 25.46, unit: .marineNauticalMiles)
    XCTAssertEqual(mediumDist.marineNauticalMilesFormatted(locale: enUSLocale), "25.5 NM")

    let largeDist = Measurement<UnitLength>(value: 150.8, unit: .marineNauticalMiles)
    XCTAssertEqual(largeDist.marineNauticalMilesFormatted(locale: enUSLocale), "151 NM")
  }

  func testMarineNauticalMilesFormatted_FrenchLocaleUsesComma() {
    let frLocale = Locale(identifier: "fr_FR")
    let dist = Measurement<UnitLength>(value: 5.23, unit: .marineNauticalMiles)
    let formatted = dist.marineNauticalMilesFormatted(locale: frLocale)
    XCTAssertTrue(formatted.contains("5,23"), "Expected comma decimal separator in French locale, got: \(formatted)")
    XCTAssertTrue(formatted.contains("NM"), "Expected NM symbol in French locale, got: \(formatted)")
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

  func testAngleNormalizationAndBearingFormatting() {
    let angle45 = Measurement<UnitAngle>(value: 45.0, unit: .degrees)
    XCTAssertEqual(angle45.marineBearingFormatted, "045°")

    let angleNegative10 = Measurement<UnitAngle>(value: -10.0, unit: .degrees)
    XCTAssertEqual(angleNegative10.normalizedDegrees, 350.0, accuracy: 0.001)
    XCTAssertEqual(angleNegative10.marineBearingFormatted, "350°")

    let angle365 = Measurement<UnitAngle>(value: 365.0, unit: .degrees)
    XCTAssertEqual(angle365.normalizedDegrees, 5.0, accuracy: 0.001)
    XCTAssertEqual(angle365.marineBearingFormatted, "005°")
  }

  func testSpeedMarineFormatting() {
    let enUSLocale = Locale(identifier: "en_US_POSIX")
    let speed = Measurement<UnitSpeed>(value: 6.24, unit: .marineKnots)
    XCTAssertEqual(speed.marineFormatted(locale: enUSLocale), "6.2 kts")
  }

  func testMaritimeCustomUnitSymbols() {
    XCTAssertEqual(UnitLength.marineNauticalMiles.symbol, "NM")
    XCTAssertEqual(UnitSpeed.marineKnots.symbol, "kts")
    XCTAssertEqual(UnitArea.marineSquareNauticalMiles.symbol, "NM²")
    XCTAssertEqual(UnitArea.squareNauticalMiles.symbol, "NM²")
  }

  func testAreaMarineFormatting() {
    let enUSLocale = Locale(identifier: "en_US_POSIX")
    let area = Measurement<UnitArea>(value: 12.345, unit: .marineSquareNauticalMiles)
    XCTAssertEqual(area.marineFormatted(locale: enUSLocale), "12.3 NM²")
  }
}

