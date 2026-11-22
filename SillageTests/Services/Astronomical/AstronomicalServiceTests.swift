//
//  AstronomicalServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

final class AstronomicalServiceTests: XCTestCase {

  private var service: AstronomicalService!

  override func setUp() async throws {
    try await super.setUp()
    service = AstronomicalService()
  }

  override func tearDown() async throws {
    service = nil
    try await super.tearDown()
  }

  // MARK: - Helpers

  private func makeDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int = 0,
    timeZone: TimeZone
  ) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = DateComponents(
      timeZone: timeZone,
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute
    )
    return try XCTUnwrap(calendar.date(from: components))
  }

  private func assertDate(
    _ actual: Date,
    matchesExpected expected: Date,
    toleranceMinutes: Double = 2.0,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let deltaSeconds = abs(actual.timeIntervalSince(expected))
    XCTAssertLessThanOrEqual(
      deltaSeconds,
      toleranceMinutes * 60.0,
      "Expected \(expected) ±\(toleranceMinutes)m, got \(actual) (delta \(Int(deltaSeconds))s)",
      file: file,
      line: line
    )
  }

  // MARK: - Reference Cases

  /// Case 1: La Rochelle (46.15°N, -1.15°W), 2026-06-21 at 00:30 Europe/Paris (UTC+2).
  /// In UTC this instant is still 2026-06-20 22:30 UTC; ephemeris must reflect June 21.
  func testLaRochelleAfterMidnightLocalTimeUsesLocalCalendarDay() async throws {
    let laRochelle = CLLocationCoordinate2D(latitude: 46.15, longitude: -1.15)
    let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
    let date = try makeDate(year: 2026, month: 6, day: 21, hour: 0, minute: 30, timeZone: paris)

    let raw = await service.calculateEphemeris(for: laRochelle, date: date, timeZone: paris)
    let ephemeris = try XCTUnwrap(raw)

    guard case let .cycle(sunrise, sunset) = ephemeris.daylight else {
      XCTFail("Expected .cycle daylight for La Rochelle, got \(ephemeris.daylight)")
      return
    }
    guard case let .cycle(dawn, dusk) = ephemeris.nauticalTwilight else {
      XCTFail("Expected .cycle nautical twilight for La Rochelle, got \(ephemeris.nauticalTwilight)")
      return
    }

    // All events must belong to June 21 in Europe/Paris
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = paris
    XCTAssertEqual(calendar.component(.day, from: sunrise), 21)
    XCTAssertEqual(calendar.component(.day, from: sunset), 21)

    XCTAssertLessThan(dawn, sunrise)
    XCTAssertLessThan(sunrise, sunset)
    XCTAssertLessThan(sunset, dusk)

    // NOAA reference values for La Rochelle (46.15°N, 1.15°W) on 2026-06-21 CEST (UTC+2)
    assertDate(dawn, matchesExpected: try makeDate(year: 2026, month: 6, day: 21, hour: 4, minute: 41, timeZone: paris))
    assertDate(sunrise, matchesExpected: try makeDate(year: 2026, month: 6, day: 21, hour: 6, minute: 13, timeZone: paris))
    assertDate(sunset, matchesExpected: try makeDate(year: 2026, month: 6, day: 21, hour: 21, minute: 59, timeZone: paris))
    assertDate(dusk, matchesExpected: try makeDate(year: 2026, month: 6, day: 21, hour: 23, minute: 31, timeZone: paris))
  }

  /// Case 2: Papeete (-17.53°S, -149.57°W), 2026-11-22 at 18:00 Pacific/Tahiti (UTC-10).
  /// In UTC this instant is already 2026-11-23 04:00 UTC; ephemeris must reflect Nov 22 Tahiti with sunrise < sunset.
  func testPapeeteEveningLocalTimeUsesLocalCalendarDayAndChronologicalOrder() async throws {
    let papeete = CLLocationCoordinate2D(latitude: -17.53, longitude: -149.57)
    let tahiti = try XCTUnwrap(TimeZone(identifier: "Pacific/Tahiti"))
    let date = try makeDate(year: 2026, month: 11, day: 22, hour: 18, minute: 0, timeZone: tahiti)

    let raw = await service.calculateEphemeris(for: papeete, date: date, timeZone: tahiti)
    let ephemeris = try XCTUnwrap(raw)

    guard case let .cycle(sunrise, sunset) = ephemeris.daylight else {
      XCTFail("Expected .cycle daylight for Papeete, got \(ephemeris.daylight)")
      return
    }
    guard case let .cycle(dawn, dusk) = ephemeris.nauticalTwilight else {
      XCTFail("Expected .cycle nautical twilight for Papeete, got \(ephemeris.nauticalTwilight)")
      return
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = tahiti
    XCTAssertEqual(calendar.component(.day, from: sunrise), 22)
    XCTAssertEqual(calendar.component(.day, from: sunset), 22)

    XCTAssertLessThan(dawn, sunrise)
    XCTAssertLessThan(sunrise, sunset)
    XCTAssertLessThan(sunset, dusk)

    // NOAA reference values for Papeete (-17.53°S, -149.57°W) on 2026-11-22 (UTC-10)
    assertDate(dawn, matchesExpected: try makeDate(year: 2026, month: 11, day: 22, hour: 4, minute: 23, timeZone: tahiti))
    assertDate(sunrise, matchesExpected: try makeDate(year: 2026, month: 11, day: 22, hour: 5, minute: 14, timeZone: tahiti))
    assertDate(sunset, matchesExpected: try makeDate(year: 2026, month: 11, day: 22, hour: 18, minute: 15, timeZone: tahiti))
    assertDate(dusk, matchesExpected: try makeDate(year: 2026, month: 11, day: 22, hour: 19, minute: 6, timeZone: tahiti))
  }

  /// Case 3: Reykjavik (64.15°N, -21.94°W), 2026-06-21 (UTC+0).
  /// Daylight has a cycle (with sunset after midnight on June 22, +1d), while nautical twilight is continuous (white nights).
  func testReykjavikSummerSolsticeHasDaylightCycleWithNextDaySunsetAndContinuousTwilight() async throws {
    let reykjavik = CLLocationCoordinate2D(latitude: 64.15, longitude: -21.94)
    let iceland = try XCTUnwrap(TimeZone(identifier: "Atlantic/Reykjavik"))
    let date = try makeDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0, timeZone: iceland)

    let raw = await service.calculateEphemeris(for: reykjavik, date: date, timeZone: iceland)
    let ephemeris = try XCTUnwrap(raw)

    guard case let .cycle(sunrise, sunset) = ephemeris.daylight else {
      XCTFail("Expected .cycle daylight for Reykjavik on June 21, got \(ephemeris.daylight)")
      return
    }
    XCTAssertEqual(ephemeris.nauticalTwilight, .continuousTwilight)
    XCTAssertLessThan(sunrise, sunset)

    // Sunrise on June 21 ~02:55 GMT, sunset after midnight on June 22 ~00:04 GMT (+1d)
    assertDate(sunrise, matchesExpected: try makeDate(year: 2026, month: 6, day: 21, hour: 2, minute: 55, timeZone: iceland))
    assertDate(sunset, matchesExpected: try makeDate(year: 2026, month: 6, day: 22, hour: 0, minute: 4, timeZone: iceland))

    // Verify +1d formatting suffix on sunset
    let formattedSunset = sunset.marineEphemerisTimeFormatted(
      relativeTo: date,
      timeZone: iceland,
      locale: Locale(identifier: "en_GB")
    )
    XCTAssertTrue(formattedSunset.hasSuffix("+1d"), "Expected +1d suffix for post-midnight sunset, got \(formattedSunset)")
  }

  /// Case 4: Longyearbyen (78.22°N, 15.63°E), 2026-06-21 -> polarDay & continuousTwilight.
  func testLongyearbyenSummerSolsticeIsPolarDayAndContinuousTwilight() async throws {
    let longyearbyen = CLLocationCoordinate2D(latitude: 78.22, longitude: 15.63)
    let tz = try XCTUnwrap(TimeZone(identifier: "Arctic/Longyearbyen"))
    let date = try makeDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0, timeZone: tz)

    let raw = await service.calculateEphemeris(for: longyearbyen, date: date, timeZone: tz)
    let ephemeris = try XCTUnwrap(raw)

    XCTAssertEqual(ephemeris.daylight, .polarDay)
    XCTAssertEqual(ephemeris.nauticalTwilight, .continuousTwilight)
    XCTAssertEqual(ephemeris.solarNoonElevation.converted(to: .degrees).value, 35.2, accuracy: 0.5)
  }

  /// Case 5a: High Arctic (79.50°N, 15.63°E), 2026-12-21 -> polarNight & continuousDark.
  /// (Note: At 78.22°N Longyearbyen, solar noon reaches -11.66° on Dec 21, just 0.34° above -12°.)
  func testHighArcticWinterSolsticeIsPolarNightAndContinuousDark() async throws {
    let highArctic = CLLocationCoordinate2D(latitude: 79.50, longitude: 15.63)
    let tz = try XCTUnwrap(TimeZone(identifier: "Arctic/Longyearbyen"))
    let date = try makeDate(year: 2026, month: 12, day: 21, hour: 12, minute: 0, timeZone: tz)

    let raw = await service.calculateEphemeris(for: highArctic, date: date, timeZone: tz)
    let ephemeris = try XCTUnwrap(raw)

    XCTAssertEqual(ephemeris.daylight, .polarNight)
    XCTAssertEqual(ephemeris.nauticalTwilight, .continuousDark)
    XCTAssertLessThan(ephemeris.solarNoonElevation.converted(to: .degrees).value, -12.0)
  }

  /// Case 5b: Longyearbyen (78.22°N, 15.63°E), 2026-12-21 -> polarNight with brief nautical twilight (noon at -11.66°).
  func testLongyearbyenWinterSolsticeIsPolarNightWithBriefNauticalTwilight() async throws {
    let longyearbyen = CLLocationCoordinate2D(latitude: 78.22, longitude: 15.63)
    let tz = try XCTUnwrap(TimeZone(identifier: "Arctic/Longyearbyen"))
    let date = try makeDate(year: 2026, month: 12, day: 21, hour: 12, minute: 0, timeZone: tz)

    let raw = await service.calculateEphemeris(for: longyearbyen, date: date, timeZone: tz)
    let ephemeris = try XCTUnwrap(raw)

    XCTAssertEqual(ephemeris.daylight, .polarNight)
    XCTAssertEqual(ephemeris.solarNoonElevation.converted(to: .degrees).value, -11.66, accuracy: 0.2)
    guard case let .cycle(dawn, dusk) = ephemeris.nauticalTwilight else {
      XCTFail("Expected brief nautical twilight at 78.22°N on Dec 21 (noon -11.66°), got \(ephemeris.nauticalTwilight)")
      return
    }
    XCTAssertLessThan(dawn, dusk)
  }

  /// Case 6: Tromsø (69.65°N, 18.96°E), 2026-12-21 -> polarNight for horizon, but .cycle(dawn, dusk) for nautical twilight.
  func testTromsoWinterSolsticeIsPolarNightWithNauticalTwilightCycle() async throws {
    let tromso = CLLocationCoordinate2D(latitude: 69.65, longitude: 18.96)
    let oslo = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
    let date = try makeDate(year: 2026, month: 12, day: 21, hour: 12, minute: 0, timeZone: oslo)

    let raw = await service.calculateEphemeris(for: tromso, date: date, timeZone: oslo)
    let ephemeris = try XCTUnwrap(raw)

    XCTAssertEqual(ephemeris.daylight, .polarNight)
    guard case let .cycle(dawn, dusk) = ephemeris.nauticalTwilight else {
      XCTFail("Expected .cycle nautical twilight for Tromsø on Dec 21, got \(ephemeris.nauticalTwilight)")
      return
    }

    XCTAssertLessThan(dawn, dusk)
    // NOAA reference values for Tromsø (69.65°N, 18.96°E) on 2026-12-21 CET (UTC+1)
    assertDate(dawn, matchesExpected: try makeDate(year: 2026, month: 12, day: 21, hour: 7, minute: 47, timeZone: oslo))
    assertDate(dusk, matchesExpected: try makeDate(year: 2026, month: 12, day: 21, hour: 15, minute: 38, timeZone: oslo))
  }

  /// Case 7: Kiritimati (1.87°N, -157.40°W), 2026-11-22 Pacific/Kiritimati (UTC+14).
  /// Near the International Date Line where |timeZoneOffset - lon/15| ≈ 24.5h > 12h;
  /// sunrise and sunset must both fall on November 22 local time with no +1d suffix.
  func testKiritimatiDateLineAlignsToLocalCalendarDayWithoutDayShift() async throws {
    let kiritimati = CLLocationCoordinate2D(latitude: 1.87, longitude: -157.40)
    let tz = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
    let date = try makeDate(year: 2026, month: 11, day: 22, hour: 12, minute: 0, timeZone: tz)

    let raw = await service.calculateEphemeris(for: kiritimati, date: date, timeZone: tz)
    let ephemeris = try XCTUnwrap(raw)

    guard case let .cycle(sunrise, sunset) = ephemeris.daylight else {
      XCTFail("Expected .cycle daylight for Kiritimati, got \(ephemeris.daylight)")
      return
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = tz
    XCTAssertEqual(calendar.component(.day, from: sunrise), 22)
    XCTAssertEqual(calendar.component(.day, from: sunset), 22)
    XCTAssertLessThan(sunrise, sunset)

    let locale = Locale(identifier: "en_GB")
    let formattedSunrise = sunrise.marineEphemerisTimeFormatted(relativeTo: date, timeZone: tz, locale: locale)
    let formattedSunset = sunset.marineEphemerisTimeFormatted(relativeTo: date, timeZone: tz, locale: locale)
    XCTAssertFalse(formattedSunrise.contains("+1d"), "Unexpected +1d suffix on Kiritimati sunrise: \(formattedSunrise)")
    XCTAssertFalse(formattedSunset.contains("+1d"), "Unexpected +1d suffix on Kiritimati sunset: \(formattedSunset)")
    XCTAssertFalse(formattedSunrise.contains("-1d"), "Unexpected -1d suffix on Kiritimati sunrise: \(formattedSunrise)")
    XCTAssertFalse(formattedSunset.contains("-1d"), "Unexpected -1d suffix on Kiritimati sunset: \(formattedSunset)")
  }

  /// Case 8: Closed-loop invariant verifying `solarElevation(for:at:)` against computed events
  /// for La Rochelle and Reykjavik on June 21.
  func testSolarElevationInvariantsForLaRochelleAndReykjavik() async throws {
    // La Rochelle (mid-latitude, both cycles active)
    let laRochelle = CLLocationCoordinate2D(latitude: 46.15, longitude: -1.15)
    let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
    let laRochelleDate = try makeDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0, timeZone: paris)
    let rawLR = await service.calculateEphemeris(for: laRochelle, date: laRochelleDate, timeZone: paris)
    let lr = try XCTUnwrap(rawLR)

    let lrNoonElevRaw = await service.solarElevation(for: laRochelle, at: lr.solarNoon)
    let lrNoonElev = try XCTUnwrap(lrNoonElevRaw)
    XCTAssertEqual(
      lrNoonElev.converted(to: .degrees).value,
      lr.solarNoonElevation.converted(to: .degrees).value,
      accuracy: 0.05
    )

    guard case let .cycle(lrSunrise, lrSunset) = lr.daylight,
          case let .cycle(lrDawn, lrDusk) = lr.nauticalTwilight else {
      XCTFail("Expected both cycles for La Rochelle")
      return
    }

    let lrSunriseElevRaw = await service.solarElevation(for: laRochelle, at: lrSunrise)
    let lrSunsetElevRaw = await service.solarElevation(for: laRochelle, at: lrSunset)
    let lrDawnElevRaw = await service.solarElevation(for: laRochelle, at: lrDawn)
    let lrDuskElevRaw = await service.solarElevation(for: laRochelle, at: lrDusk)

    let lrSunriseElev = try XCTUnwrap(lrSunriseElevRaw)
    let lrSunsetElev = try XCTUnwrap(lrSunsetElevRaw)
    let lrDawnElev = try XCTUnwrap(lrDawnElevRaw)
    let lrDuskElev = try XCTUnwrap(lrDuskElevRaw)

    XCTAssertEqual(lrSunriseElev.converted(to: .degrees).value, -0.833, accuracy: 0.1)
    XCTAssertEqual(lrSunsetElev.converted(to: .degrees).value, -0.833, accuracy: 0.1)
    XCTAssertEqual(lrDawnElev.converted(to: .degrees).value, -12.0, accuracy: 0.1)
    XCTAssertEqual(lrDuskElev.converted(to: .degrees).value, -12.0, accuracy: 0.1)

    // Reykjavik (high-latitude summer solstice, 2-pass precision check)
    let reykjavik = CLLocationCoordinate2D(latitude: 64.15, longitude: -21.94)
    let iceland = try XCTUnwrap(TimeZone(identifier: "Atlantic/Reykjavik"))
    let reykjavikDate = try makeDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0, timeZone: iceland)
    let rawRvk = await service.calculateEphemeris(for: reykjavik, date: reykjavikDate, timeZone: iceland)
    let rvk = try XCTUnwrap(rawRvk)

    let rvkNoonElevRaw = await service.solarElevation(for: reykjavik, at: rvk.solarNoon)
    let rvkNoonElev = try XCTUnwrap(rvkNoonElevRaw)
    XCTAssertEqual(
      rvkNoonElev.converted(to: .degrees).value,
      rvk.solarNoonElevation.converted(to: .degrees).value,
      accuracy: 0.05
    )

    guard case let .cycle(rvkSunrise, rvkSunset) = rvk.daylight else {
      XCTFail("Expected .cycle daylight for Reykjavik")
      return
    }

    let rvkSunriseElevRaw = await service.solarElevation(for: reykjavik, at: rvkSunrise)
    let rvkSunsetElevRaw = await service.solarElevation(for: reykjavik, at: rvkSunset)
    let rvkSunriseElev = try XCTUnwrap(rvkSunriseElevRaw)
    let rvkSunsetElev = try XCTUnwrap(rvkSunsetElevRaw)
    XCTAssertEqual(rvkSunriseElev.converted(to: .degrees).value, -0.833, accuracy: 0.1)
    XCTAssertEqual(rvkSunsetElev.converted(to: .degrees).value, -0.833, accuracy: 0.1)
  }

  // MARK: - Edge Cases & Concurrency

  func testInvalidCoordinateReturnsNil() async throws {
    let date = try makeDate(year: 2026, month: 6, day: 21, hour: 12, timeZone: .gmt)

    let invalidCoord1 = CLLocationCoordinate2D(latitude: 100.0, longitude: 0.0)
    let ephemeris1 = await service.calculateEphemeris(for: invalidCoord1, date: date, timeZone: .gmt)
    XCTAssertNil(ephemeris1)

    let invalidCoord2 = CLLocationCoordinate2D(latitude: -95.0, longitude: 200.0)
    let ephemeris2 = await service.calculateEphemeris(for: invalidCoord2, date: date, timeZone: .gmt)
    XCTAssertNil(ephemeris2)
  }

  func testExactNorthPoleDoesNotProduceNaN() async throws {
    let northPole = CLLocationCoordinate2D(latitude: 90.0, longitude: 0.0)
    let summer = try makeDate(year: 2026, month: 6, day: 21, hour: 12, timeZone: .gmt)
    let winter = try makeDate(year: 2026, month: 12, day: 21, hour: 12, timeZone: .gmt)

    let rawSummer = await service.calculateEphemeris(for: northPole, date: summer, timeZone: .gmt)
    let summerEphem = try XCTUnwrap(rawSummer)
    XCTAssertEqual(summerEphem.daylight, .polarDay)
    XCTAssertEqual(summerEphem.nauticalTwilight, .continuousTwilight)
    XCTAssertFalse(summerEphem.solarNoonElevation.value.isNaN)

    let rawWinter = await service.calculateEphemeris(for: northPole, date: winter, timeZone: .gmt)
    let winterEphem = try XCTUnwrap(rawWinter)
    XCTAssertEqual(winterEphem.daylight, .polarNight)
    XCTAssertEqual(winterEphem.nauticalTwilight, .continuousDark)
    XCTAssertFalse(winterEphem.solarNoonElevation.value.isNaN)
  }

  func testSunEphemerisSendableAcrossTasks() async throws {
    let coordinate = CLLocationCoordinate2D(latitude: 43.2965, longitude: 5.3698) // Marseille
    let date = try makeDate(year: 2026, month: 6, day: 21, hour: 12, timeZone: .gmt)
    let ephemeris = await service.calculateEphemeris(for: coordinate, date: date, timeZone: .gmt)

    let sendableCopy = await Task.detached { () -> SunEphemeris? in
      return ephemeris
    }.value

    XCTAssertEqual(ephemeris, sendableCopy)
  }

  @MainActor
  func testDisplayRowsAlwaysKeepFourFixedRowsAndFooterForPolarStates() throws {
    let ref = try makeDate(year: 2026, month: 6, day: 21, hour: 12, timeZone: .gmt)
    let dawn = try makeDate(year: 2026, month: 6, day: 21, hour: 4, timeZone: .gmt)
    let sunrise = try makeDate(year: 2026, month: 6, day: 21, hour: 6, timeZone: .gmt)
    let sunset = try makeDate(year: 2026, month: 6, day: 21, hour: 20, timeZone: .gmt)
    let dusk = try makeDate(year: 2026, month: 6, day: 21, hour: 22, timeZone: .gmt)
    let noonElevation = Measurement(value: 45, unit: UnitAngle.degrees)

    // nil ephemeris -> 4 missing rows, no footer
    let nilRows = SunEphemerisDisplayRow.rows(for: nil)
    XCTAssertEqual(nilRows.map(\.id), ["dawn", "sunrise", "sunset", "dusk"])
    XCTAssertTrue(nilRows.allSatisfy { $0.value == .missing })
    XCTAssertNil(SunEphemerisDisplayRow.footerText(for: nil))

    // Standard cycle -> 4 time rows, no footer
    let standard = SunEphemeris(
      daylight: .cycle(sunrise: sunrise, sunset: sunset),
      nauticalTwilight: .cycle(dawn: dawn, dusk: dusk),
      solarNoon: ref,
      solarNoonElevation: noonElevation,
      referenceDate: ref,
      timeZone: .gmt
    )
    let standardRows = SunEphemerisDisplayRow.rows(for: standard)
    XCTAssertEqual(standardRows.map(\.id), ["dawn", "sunrise", "sunset", "dusk"])
    XCTAssertEqual(standardRows[0].value, .time(dawn, referenceDate: ref, timeZone: .gmt))
    XCTAssertEqual(standardRows[1].value, .time(sunrise, referenceDate: ref, timeZone: .gmt))
    XCTAssertEqual(standardRows[2].value, .time(sunset, referenceDate: ref, timeZone: .gmt))
    XCTAssertEqual(standardRows[3].value, .time(dusk, referenceDate: ref, timeZone: .gmt))
    XCTAssertNil(SunEphemerisDisplayRow.footerText(for: standard))

    // Polar night with nautical twilight cycle -> sunrise/sunset unavailable, dawn/dusk times, Polar Night footer
    let polarNightWithTwilight = SunEphemeris(
      daylight: .polarNight,
      nauticalTwilight: .cycle(dawn: dawn, dusk: dusk),
      solarNoon: ref,
      solarNoonElevation: noonElevation,
      referenceDate: ref,
      timeZone: .gmt
    )
    let polarNightRows = SunEphemerisDisplayRow.rows(for: polarNightWithTwilight)
    XCTAssertEqual(polarNightRows.map(\.id), ["dawn", "sunrise", "sunset", "dusk"])
    XCTAssertEqual(polarNightRows[0].value, .time(dawn, referenceDate: ref, timeZone: .gmt))
    XCTAssertEqual(polarNightRows[1].value, .unavailable)
    XCTAssertEqual(polarNightRows[2].value, .unavailable)
    XCTAssertEqual(polarNightRows[3].value, .time(dusk, referenceDate: ref, timeZone: .gmt))
    XCTAssertEqual(SunEphemerisDisplayRow.footerText(for: polarNightWithTwilight), String(localized: "Polar Night"))

    // Standard daylight with continuous twilight -> dawn/dusk unavailable, sunrise/sunset times, No Nautical Night footer
    let whiteNight = SunEphemeris(
      daylight: .cycle(sunrise: sunrise, sunset: sunset),
      nauticalTwilight: .continuousTwilight,
      solarNoon: ref,
      solarNoonElevation: noonElevation,
      referenceDate: ref,
      timeZone: .gmt
    )
    let whiteNightRows = SunEphemerisDisplayRow.rows(for: whiteNight)
    XCTAssertEqual(whiteNightRows.map(\.id), ["dawn", "sunrise", "sunset", "dusk"])
    XCTAssertEqual(whiteNightRows[0].value, .unavailable)
    XCTAssertEqual(whiteNightRows[1].value, .time(sunrise, referenceDate: ref, timeZone: .gmt))
    XCTAssertEqual(whiteNightRows[2].value, .time(sunset, referenceDate: ref, timeZone: .gmt))
    XCTAssertEqual(whiteNightRows[3].value, .unavailable)
    XCTAssertEqual(SunEphemerisDisplayRow.footerText(for: whiteNight), String(localized: "No Nautical Night"))

    // Polar day + continuous twilight -> all 4 unavailable, concise Polar Day footer
    let polarDay = SunEphemeris(
      daylight: .polarDay,
      nauticalTwilight: .continuousTwilight,
      solarNoon: ref,
      solarNoonElevation: noonElevation,
      referenceDate: ref,
      timeZone: .gmt
    )
    let polarDayRows = SunEphemerisDisplayRow.rows(for: polarDay)
    XCTAssertEqual(polarDayRows.map(\.id), ["dawn", "sunrise", "sunset", "dusk"])
    XCTAssertTrue(polarDayRows.allSatisfy { $0.value == .unavailable })
    XCTAssertEqual(SunEphemerisDisplayRow.footerText(for: polarDay), String(localized: "Polar Day"))

    // Polar night + continuous dark -> all 4 unavailable, combined footer
    let polarNightDark = SunEphemeris(
      daylight: .polarNight,
      nauticalTwilight: .continuousDark,
      solarNoon: ref,
      solarNoonElevation: noonElevation,
      referenceDate: ref,
      timeZone: .gmt
    )
    let polarNightDarkRows = SunEphemerisDisplayRow.rows(for: polarNightDark)
    XCTAssertEqual(polarNightDarkRows.map(\.id), ["dawn", "sunrise", "sunset", "dusk"])
    XCTAssertTrue(polarNightDarkRows.allSatisfy { $0.value == .unavailable })
    XCTAssertEqual(
      SunEphemerisDisplayRow.footerText(for: polarNightDark),
      "\(String(localized: "Polar Night")) • \(String(localized: "Continuous Dark"))"
    )
  }
}
