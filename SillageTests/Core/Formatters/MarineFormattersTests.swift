//
//  MarineFormattersTests.swift
//  SillageTests
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreLocation
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

    let angleWrap = Measurement<UnitAngle>(value: 359.6, unit: .degrees)
    XCTAssertEqual(angleWrap.marineBearingFormatted, "000°")

    let angleNaN = Measurement<UnitAngle>(value: .nan, unit: .degrees)
    XCTAssertEqual(angleNaN.marineBearingFormatted, "---")

    let angleInf = Measurement<UnitAngle>(value: .infinity, unit: .degrees)
    XCTAssertEqual(angleInf.marineBearingFormatted, "---")
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

  func testFileSizeFormatting() {
    let enUS = Locale(identifier: "en_US")
    let frFR = Locale(identifier: "fr_FR")

    let b500 = Measurement<UnitInformationStorage>(value: 500, unit: .bytes)
    let kb25 = Measurement<UnitInformationStorage>(value: 25_000, unit: .bytes)
    let mb15 = Measurement<UnitInformationStorage>(value: 15_400_000, unit: .bytes)
    let gb3 = Measurement<UnitInformationStorage>(value: 3_200_000_000, unit: .bytes)

    let formatted500 = b500.marineFormatted(locale: enUS)
    XCTAssertTrue(formatted500.contains("500"), "Expected 500 in result: \(formatted500)")

    let formattedKB = kb25.marineFormatted(locale: enUS)
    XCTAssertTrue(formattedKB.contains("25"), "Expected 25 in result: \(formattedKB)")
    XCTAssertTrue(formattedKB.localizedCaseInsensitiveContains("kb"), "Expected KB/kB in result: \(formattedKB)")

    let formattedMB = mb15.marineFormatted(locale: enUS)
    XCTAssertTrue(formattedMB.contains("15"), "Expected 15 in result: \(formattedMB)")
    XCTAssertTrue(formattedMB.contains("MB"), "Expected MB in result: \(formattedMB)")

    let formattedGB = gb3.marineFormatted(locale: enUS)
    XCTAssertTrue(formattedGB.contains("3"), "Expected 3 in result: \(formattedGB)")
    XCTAssertTrue(formattedGB.contains("GB"), "Expected GB in result: \(formattedGB)")

    // French locale uses Mo and comma separator
    let frMB = mb15.marineFormatted(locale: frFR)
    XCTAssertTrue(frMB.contains("15,4") || frMB.contains("15"), "Expected French value in result: \(frMB)")
    XCTAssertTrue(frMB.contains("Mo"), "Expected Mo in French locale, got: \(frMB)")

    // Unit conversion input test
    let megaMeasurement = Measurement<UnitInformationStorage>(value: 50, unit: .megabytes)
    let formattedMega = megaMeasurement.marineFormatted(locale: enUS)
    XCTAssertTrue(formattedMega.contains("50"), "Expected 50 in result: \(formattedMega)")
    XCTAssertTrue(formattedMega.contains("MB"), "Expected MB in result: \(formattedMega)")

    // Direct BinaryInteger test (Int64, Int)
    let rawBytes: Int64 = 15_400_000
    let formattedInt64 = rawBytes.marineFormatted(locale: enUS)
    XCTAssertTrue(formattedInt64.contains("15"), "Expected 15 in result: \(formattedInt64)")
    XCTAssertTrue(formattedInt64.contains("MB"), "Expected MB in result: \(formattedInt64)")
  }

  func testMarineDeclinationFormatted() {
    let westDecl = Measurement<UnitAngle>(value: -1.5, unit: .degrees)
    XCTAssertEqual(westDecl.marineDeclinationFormatted, "1.5° W")

    let eastDecl = Measurement<UnitAngle>(value: 3.2, unit: .degrees)
    XCTAssertEqual(eastDecl.marineDeclinationFormatted, "3.2° E")

    let zeroDecl = Measurement<UnitAngle>(value: 0.0, unit: .degrees)
    XCTAssertEqual(zeroDecl.marineDeclinationFormatted, "0.0°")

    let nearZeroEast = Measurement<UnitAngle>(value: 0.01, unit: .degrees)
    XCTAssertEqual(nearZeroEast.marineDeclinationFormatted, "0.0°")

    let nearZeroWest = Measurement<UnitAngle>(value: -0.04, unit: .degrees)
    XCTAssertEqual(nearZeroWest.marineDeclinationFormatted, "0.0°")

    let boundaryEast = Measurement<UnitAngle>(value: 0.05, unit: .degrees)
    XCTAssertEqual(boundaryEast.marineDeclinationFormatted, "0.1° E")

    let boundaryWest = Measurement<UnitAngle>(value: -0.05, unit: .degrees)
    XCTAssertEqual(boundaryWest.marineDeclinationFormatted, "0.1° W")

    let nanDecl = Measurement<UnitAngle>(value: .nan, unit: .degrees)
    XCTAssertEqual(nanDecl.marineDeclinationFormatted, "---")

    let overflowDecl = Measurement<UnitAngle>(value: .greatestFiniteMagnitude, unit: .degrees)
    XCTAssertEqual(overflowDecl.marineDeclinationFormatted, "---")
  }

  func testMarineDeclinationConversionFooter() {
    let eastDecl = Measurement<UnitAngle>(value: 1.2, unit: .degrees)
    XCTAssertEqual(
      eastDecl.marineDeclinationConversionFooter,
      "True to Magnetic: subtract 1.2° • Magnetic to True: add 1.2°"
    )

    let westDecl = Measurement<UnitAngle>(value: -2.5, unit: .degrees)
    XCTAssertEqual(
      westDecl.marineDeclinationConversionFooter,
      "True to Magnetic: add 2.5° • Magnetic to True: subtract 2.5°"
    )

    let zeroDecl = Measurement<UnitAngle>(value: 0.0, unit: .degrees)
    XCTAssertEqual(
      zeroDecl.marineDeclinationConversionFooter,
      "No significant variation between True and Magnetic bearings."
    )

    let nearZeroEast = Measurement<UnitAngle>(value: 0.04, unit: .degrees)
    XCTAssertEqual(
      nearZeroEast.marineDeclinationConversionFooter,
      "No significant variation between True and Magnetic bearings."
    )

    let nearZeroWest = Measurement<UnitAngle>(value: -0.04, unit: .degrees)
    XCTAssertEqual(
      nearZeroWest.marineDeclinationConversionFooter,
      "No significant variation between True and Magnetic bearings."
    )
  }

  func testMarineTimeWithTimeZoneFormatted() {
    guard let utc = TimeZone(identifier: "UTC") else {
      XCTFail("Missing UTC timezone")
      return
    }
    var components = DateComponents()
    components.year = 2026
    components.month = 6
    components.day = 21
    components.hour = 12
    components.minute = 30
    components.timeZone = utc
    let calendar = Calendar(identifier: .gregorian)
    guard let date = calendar.date(from: components) else {
      XCTFail("Failed to create date")
      return
    }

    let formattedUTC = date.marineTimeWithTimeZoneFormatted(timeZone: utc)
    let expectedAbbr = utc.abbreviation(for: date) ?? "UTC"
    XCTAssertTrue(formattedUTC.contains(expectedAbbr), "Expected \(expectedAbbr) in \(formattedUTC)")
  }

  func testEphemerisTimeDayOffsetSuffix() throws {
    let utc = TimeZone.gmt
    let locale = Locale(identifier: "en_GB")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc

    let refDate = try XCTUnwrap(calendar.date(from: DateComponents(timeZone: utc, year: 2026, month: 6, day: 21, hour: 12, minute: 0)))
    let sameDay = try XCTUnwrap(calendar.date(from: DateComponents(timeZone: utc, year: 2026, month: 6, day: 21, hour: 6, minute: 15)))
    let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(timeZone: utc, year: 2026, month: 6, day: 22, hour: 0, minute: 3)))
    let prevDay = try XCTUnwrap(calendar.date(from: DateComponents(timeZone: utc, year: 2026, month: 6, day: 20, hour: 23, minute: 45)))

    let sameFormatted = sameDay.marineEphemerisTimeFormatted(relativeTo: refDate, timeZone: utc, locale: locale)
    XCTAssertFalse(sameFormatted.contains("+1d"))
    XCTAssertFalse(sameFormatted.contains("-1d"))

    let nextFormatted = nextDay.marineEphemerisTimeFormatted(relativeTo: refDate, timeZone: utc, locale: locale)
    XCTAssertTrue(nextFormatted.hasSuffix(" +1d"), "Expected ' +1d' suffix in \(nextFormatted)")

    let prevFormatted = prevDay.marineEphemerisTimeFormatted(relativeTo: refDate, timeZone: utc, locale: locale)
    XCTAssertTrue(prevFormatted.hasSuffix(" -1d"), "Expected ' -1d' suffix in \(prevFormatted)")
  }

  func testFileSizeFormattingEdgeCasesDoNotCrash() {
    let enUS = Locale(identifier: "en_US")
    let zeroFormatted = Int64(0).marineFormatted(locale: enUS)
    let maxFormatted = Int64.max.marineFormatted(locale: enUS)

    // Valid zero stays formatted as 0 bytes (not "---")
    XCTAssertNotEqual(zeroFormatted, "---")
    XCTAssertEqual(
      Measurement<UnitInformationStorage>(value: 0, unit: .bytes).marineFormatted(locale: enUS),
      zeroFormatted
    )

    // BinaryInteger overflow clamps to Int64.max; negative values return "---"
    XCTAssertEqual(UInt64.max.marineFormatted(locale: enUS), maxFormatted)
    XCTAssertEqual(Int64.min.marineFormatted(locale: enUS), "---")
    XCTAssertEqual((-42).marineFormatted(locale: enUS), "---")

    // UnitInformationStorage non-finite and negative values return "---"
    let nanBytes = Measurement<UnitInformationStorage>(value: .nan, unit: .bytes)
    XCTAssertEqual(nanBytes.marineFormatted(locale: enUS), "---")

    let infBytes = Measurement<UnitInformationStorage>(value: .infinity, unit: .bytes)
    XCTAssertEqual(infBytes.marineFormatted(locale: enUS), "---")

    let negInfBytes = Measurement<UnitInformationStorage>(value: -.infinity, unit: .bytes)
    XCTAssertEqual(negInfBytes.marineFormatted(locale: enUS), "---")

    let negBytes = Measurement<UnitInformationStorage>(value: -1024, unit: .bytes)
    XCTAssertEqual(negBytes.marineFormatted(locale: enUS), "---")

    // Finite values >= Double(Int64.max) clamp to Int64.max
    let doubleInt64MaxBytes = Measurement<UnitInformationStorage>(value: Double(Int64.max), unit: .bytes)
    XCTAssertEqual(doubleInt64MaxBytes.marineFormatted(locale: enUS), maxFormatted)

    let hugeBytes = Measurement<UnitInformationStorage>(value: 1e30, unit: .bytes)
    XCTAssertEqual(hugeBytes.marineFormatted(locale: enUS), maxFormatted)
  }

  func testCoordinateFormatStyleStandardAndLongitudePadding() {
    let north = String(localized: "N", comment: "North cardinal point")
    let south = String(localized: "S", comment: "South cardinal point")
    let east = String(localized: "E", comment: "East cardinal point")
    let west = String(localized: "W", comment: "West cardinal point")

    let nwCoord = CLLocationCoordinate2D(latitude: 47.5, longitude: -(3.0 + 5.12 / 60.0))
    XCTAssertEqual(nwCoord.formatted(.marineCoordinate), "47° 30.000' \(north) / 003° 05.120' \(west)")

    let seCoord = CLLocationCoordinate2D(latitude: -(12.0 + 34.567 / 60.0), longitude: 123.0 + 27.407 / 60.0)
    XCTAssertEqual(seCoord.formatted(.marineCoordinate), "12° 34.567' \(south) / 123° 27.407' \(east)")

    let originCoord = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
    XCTAssertEqual(originCoord.formatted(.marineCoordinate), "00° 00.000' \(north) / 000° 00.000' \(east)")
  }

  func testCoordinateFormatStyleRoundingCarriesMinutesToDegrees() {
    let north = String(localized: "N", comment: "North cardinal point")
    let west = String(localized: "W", comment: "West cardinal point")

    let nearNextDegreeLat = 47.0 + 59.9996 / 60.0
    let nearNextDegreeLon = -(2.0 + 59.9999 / 60.0)
    let coord = CLLocationCoordinate2D(latitude: nearNextDegreeLat, longitude: nearNextDegreeLon)
    let formatted = coord.formatted(.marineCoordinate)

    XCTAssertFalse(formatted.contains("60.000'"), "Minutes must carry over to degrees instead of displaying 60.000': \(formatted)")
    XCTAssertEqual(formatted, "48° 00.000' \(north) / 003° 00.000' \(west)")
  }

  func testCoordinateFormatStyleInvalidAndOutOfBoundsValuesReturnPlaceholder() {
    let placeholder = "--° --.---' / ---° --.---'"

    XCTAssertEqual(kCLLocationCoordinate2DInvalid.formatted(.marineCoordinate), placeholder)
    XCTAssertEqual(CLLocationCoordinate2D(latitude: 90.1, longitude: 0.0).formatted(.marineCoordinate), placeholder)
    XCTAssertEqual(CLLocationCoordinate2D(latitude: 0.0, longitude: -180.1).formatted(.marineCoordinate), placeholder)
    XCTAssertEqual(CLLocationCoordinate2D(latitude: .nan, longitude: .infinity).formatted(.marineCoordinate), placeholder)
  }
}

