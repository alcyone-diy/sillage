//
//  AstronomicalService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Actor responsible for offline astronomical calculations (solar ephemerides and nautical twilight)
/// using the NOAA / Jean Meeus solar position algorithm.
public actor AstronomicalService {

  /// Standard solar elevation at sunrise/sunset (-0.833° = -50': 34' atmospheric refraction + 16' solar semi-diameter).
  private static let horizonElevation = Measurement(value: -0.833, unit: UnitAngle.degrees)

  /// Standard solar elevation at nautical twilight (-12.0°).
  private static let nauticalTwilightElevation = Measurement(value: -12.0, unit: UnitAngle.degrees)

  private static let unixEpochJulianDay: Double = 2_440_587.5
  private static let j2000JulianDay: Double = 2_451_545.0
  private static let daysPerJulianCentury: Double = 36_525.0
  private static let secondsPerDay: Double = 86_400.0
  private static let minutesPerDegree: Double = 4.0

  public init() {}

  /// Calculates solar ephemeris (daylight cycle and nautical twilight) for the specified coordinate, date, and time zone.
  ///
  /// The calculation extracts the calendar date `(year, month, day)` of `date` in `timeZone`,
  /// anchors on local solar noon for that calendar date and longitude, and performs a 2-pass
  /// NOAA/Meeus refinement for each rise/set event.
  ///
  /// - Parameters:
  ///   - coordinate: The geographical coordinate (`CLLocationCoordinate2D`, East-positive longitude).
  ///   - date: The reference instant whose calendar date in `timeZone` determines the solar day.
  ///   - timeZone: The explicit time zone defining the calendar day for `date`.
  /// - Returns: A `SunEphemeris`, or `nil` if the coordinate is invalid.
  public func calculateEphemeris(
    for coordinate: CLLocationCoordinate2D,
    date: Date = Date(),
    timeZone: TimeZone
  ) -> SunEphemeris? {
    guard CLLocationCoordinate2DIsValid(coordinate) else {
      return nil
    }

    var localCalendar = Calendar(identifier: .gregorian)
    localCalendar.timeZone = timeZone
    let dateComponents = localCalendar.dateComponents([.year, .month, .day], from: date)

    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = .gmt
    guard let rawMidnightUTC = utcCalendar.date(
      from: DateComponents(
        year: dateComponents.year,
        month: dateComponents.month,
        day: dateComponents.day,
        hour: 0,
        minute: 0,
        second: 0
      )
    ) else {
      return nil
    }

    let latitude = Measurement(value: coordinate.latitude, unit: UnitAngle.degrees)
    let longitude = Measurement(value: coordinate.longitude, unit: UnitAngle.degrees)

    // Align the solar day anchor to the transit closest (±12h) to civil noon in `timeZone`.
    // Prevents ±24h day shifts near the International Date Line (e.g. Kiritimati UTC+14 at -157.4°W)
    // or when inspecting a distant waypoint in an opposite hemisphere's time zone.
    let meanSolarNoonMinutes = 720.0 - Self.minutesPerDegree * longitude.value
    let localNoon = localCalendar.startOfDay(for: date).addingTimeInterval(12.0 * 3600.0)
    let rawApproxNoon = rawMidnightUTC.addingTimeInterval(meanSolarNoonMinutes * 60.0)
    let dayShift = (rawApproxNoon.timeIntervalSince(localNoon) / Self.secondsPerDay).rounded()
    let midnightUTC = rawMidnightUTC.addingTimeInterval(-dayShift * Self.secondsPerDay)

    // Pass 1: mean solar noon for the aligned solar day at this longitude
    let approxNoon = midnightUTC.addingTimeInterval(meanSolarNoonMinutes * 60.0)
    let approxParams = Self.solarParameters(at: approxNoon)

    // Pass 2: refined true solar noon
    let solarNoonMinutesPass1 = meanSolarNoonMinutes - approxParams.equationOfTimeMinutes
    let solarNoonPass1 = midnightUTC.addingTimeInterval(solarNoonMinutesPass1 * 60.0)
    let noonParams = Self.solarParameters(at: solarNoonPass1)
    let solarNoonMinutes = meanSolarNoonMinutes - noonParams.equationOfTimeMinutes
    let solarNoon = midnightUTC.addingTimeInterval(solarNoonMinutes * 60.0)

    let solarNoonElevation = Self.solarElevationAtNoon(
      latitude: latitude,
      declination: noonParams.declination
    )

    let daylight = Self.computeDaylightState(
      latitude: latitude,
      longitude: longitude,
      midnightUTC: midnightUTC,
      noonParams: noonParams,
      solarNoonElevation: solarNoonElevation
    )

    let nauticalTwilight = Self.computeNauticalTwilightState(
      latitude: latitude,
      longitude: longitude,
      midnightUTC: midnightUTC,
      noonParams: noonParams,
      solarNoonElevation: solarNoonElevation
    )

    return SunEphemeris(
      daylight: daylight,
      nauticalTwilight: nauticalTwilight,
      solarNoon: solarNoon,
      solarNoonElevation: solarNoonElevation,
      referenceDate: date,
      timeZone: timeZone
    )
  }

  /// Calculates the solar elevation angle at a specific instant and coordinate.
  public func solarElevation(
    for coordinate: CLLocationCoordinate2D,
    at date: Date
  ) -> Measurement<UnitAngle>? {
    guard CLLocationCoordinate2DIsValid(coordinate) else {
      return nil
    }

    let latitude = Measurement(value: coordinate.latitude, unit: UnitAngle.degrees)
    let longitude = Measurement(value: coordinate.longitude, unit: UnitAngle.degrees)
    let params = Self.solarParameters(at: date)

    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = .gmt
    let startOfUTCDay = utcCalendar.startOfDay(for: date)
    let utcMinutes = date.timeIntervalSince(startOfUTCDay) / 60.0

    let trueSolarTimeMinutes = (utcMinutes + params.equationOfTimeMinutes + Self.minutesPerDegree * longitude.value)
      .truncatingRemainder(dividingBy: 1440.0)
    let normalizedTrueSolarTime = trueSolarTimeMinutes < 0 ? trueSolarTimeMinutes + 1440.0 : trueSolarTimeMinutes
    let hourAngle = Measurement(value: normalizedTrueSolarTime / Self.minutesPerDegree - 180.0, unit: UnitAngle.degrees)

    let sinElev = Self.sin(latitude) * Self.sin(params.declination)
      + Self.cos(latitude) * Self.cos(params.declination) * Self.cos(hourAngle)
    return Self.asinAngle(min(1.0, max(-1.0, sinElev)))
  }

  // MARK: - NOAA / Jean Meeus Core

  private struct SolarParameters: Sendable {
    let declination: Measurement<UnitAngle>
    let equationOfTimeMinutes: Double
  }

  private enum HourAngleResult: Sendable {
    case angle(Measurement<UnitAngle>)
    case alwaysAbove
    case alwaysBelow
  }

  private enum BandResolution: Sendable {
    case cycle(start: Date, end: Date)
    case alwaysAbove
    case alwaysBelow
  }

  private static func computeDaylightState(
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>,
    midnightUTC: Date,
    noonParams: SolarParameters,
    solarNoonElevation: Measurement<UnitAngle>
  ) -> SolarDaylightState {
    switch resolveBand(
      targetElevation: horizonElevation,
      latitude: latitude,
      longitude: longitude,
      midnightUTC: midnightUTC,
      noonParams: noonParams,
      solarNoonElevation: solarNoonElevation
    ) {
    case let .cycle(start, end):
      return .cycle(sunrise: start, sunset: end)
    case .alwaysAbove:
      return .polarDay
    case .alwaysBelow:
      return .polarNight
    }
  }

  private static func computeNauticalTwilightState(
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>,
    midnightUTC: Date,
    noonParams: SolarParameters,
    solarNoonElevation: Measurement<UnitAngle>
  ) -> NauticalTwilightState {
    switch resolveBand(
      targetElevation: nauticalTwilightElevation,
      latitude: latitude,
      longitude: longitude,
      midnightUTC: midnightUTC,
      noonParams: noonParams,
      solarNoonElevation: solarNoonElevation
    ) {
    case let .cycle(start, end):
      return .cycle(dawn: start, dusk: end)
    case .alwaysAbove:
      return .continuousTwilight
    case .alwaysBelow:
      return .continuousDark
    }
  }

  /// Resolves rise/set crossings for `targetElevation` around local solar noon using a 2-pass refinement.
  private static func resolveBand(
    targetElevation: Measurement<UnitAngle>,
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>,
    midnightUTC: Date,
    noonParams: SolarParameters,
    solarNoonElevation: Measurement<UnitAngle>
  ) -> BandResolution {
    let meanSolarNoonMinutes = 720.0 - minutesPerDegree * longitude.value

    // Pass 1: estimate using solar noon parameters
    let pass1 = hourAngle(
      latitude: latitude,
      declination: noonParams.declination,
      targetElevation: targetElevation,
      solarNoonElevation: solarNoonElevation
    )

    let ha1Degrees: Double
    switch pass1 {
    case .alwaysAbove:
      return .alwaysAbove
    case .alwaysBelow:
      return .alwaysBelow
    case let .angle(ha):
      ha1Degrees = ha.converted(to: .degrees).value
    }

    let approxRiseMinutes = meanSolarNoonMinutes - noonParams.equationOfTimeMinutes - minutesPerDegree * ha1Degrees
    let approxSetMinutes = meanSolarNoonMinutes - noonParams.equationOfTimeMinutes + minutesPerDegree * ha1Degrees

    let approxRiseDate = midnightUTC.addingTimeInterval(approxRiseMinutes * 60.0)
    let approxSetDate = midnightUTC.addingTimeInterval(approxSetMinutes * 60.0)

    // Pass 2: refine each event at its estimated instant (high-latitude precision < 1 min)
    let riseParams = solarParameters(at: approxRiseDate)
    let setParams = solarParameters(at: approxSetDate)

    let riseNoonElev = solarElevationAtNoon(latitude: latitude, declination: riseParams.declination)
    let setNoonElev = solarElevationAtNoon(latitude: latitude, declination: setParams.declination)

    let riseHA = hourAngle(
      latitude: latitude,
      declination: riseParams.declination,
      targetElevation: targetElevation,
      solarNoonElevation: riseNoonElev
    )
    let setHA = hourAngle(
      latitude: latitude,
      declination: setParams.declination,
      targetElevation: targetElevation,
      solarNoonElevation: setNoonElev
    )

    // Handle transition days where pass 2 moves cos(H) outside [-1, 1] without ever producing NaN
    switch (riseHA, setHA) {
    case let (.angle(riseAngle), .angle(setAngle)):
      let riseMinutes = meanSolarNoonMinutes
        - riseParams.equationOfTimeMinutes
        - minutesPerDegree * riseAngle.converted(to: .degrees).value
      let setMinutes = meanSolarNoonMinutes
        - setParams.equationOfTimeMinutes
        + minutesPerDegree * setAngle.converted(to: .degrees).value
      return .cycle(
        start: midnightUTC.addingTimeInterval(riseMinutes * 60.0),
        end: midnightUTC.addingTimeInterval(setMinutes * 60.0)
      )
    case (.alwaysAbove, _), (_, .alwaysAbove):
      return .alwaysAbove
    case (.alwaysBelow, _), (_, .alwaysBelow):
      return .alwaysBelow
    }
  }

  /// Computes NOAA/Meeus solar declination and equation of time (minutes) for a given UTC instant.
  private static func solarParameters(at date: Date) -> SolarParameters {
    let julianDay = date.timeIntervalSince1970 / secondsPerDay + unixEpochJulianDay
    let t = (julianDay - j2000JulianDay) / daysPerJulianCentury

    // Geometric Mean Longitude of the Sun (degrees, normalized to [0, 360))
    let rawL0 = 280.46646 + t * (36000.76983 + t * 0.0003032)
    let normalizedL0 = rawL0.truncatingRemainder(dividingBy: 360.0)
    let l0 = Measurement(value: normalizedL0 < 0 ? normalizedL0 + 360.0 : normalizedL0, unit: UnitAngle.degrees)

    // Geometric Mean Anomaly of the Sun (degrees)
    let m = Measurement(value: 357.52911 + t * (35999.05029 - 0.0001537 * t), unit: UnitAngle.degrees)

    // Eccentricity of Earth's Orbit (dimensionless)
    let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)

    // Sun Equation of Center (degrees)
    let m2 = Measurement(value: 2.0 * m.value, unit: UnitAngle.degrees)
    let m3 = Measurement(value: 3.0 * m.value, unit: UnitAngle.degrees)
    let eqOfCenterDeg = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
      + sin(m2) * (0.019993 - 0.000101 * t)
      + sin(m3) * 0.000289

    // Sun True Longitude & Apparent Longitude (degrees)
    let trueLongDeg = l0.value + eqOfCenterDeg
    let omega = Measurement(value: 125.04 - 1934.136 * t, unit: UnitAngle.degrees)
    let apparentLong = Measurement(value: trueLongDeg - 0.00569 - 0.00478 * sin(omega), unit: UnitAngle.degrees)

    // Mean Obliquity & Corrected Obliquity of the Ecliptic (degrees)
    let meanObliqDeg = 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
    let obliqCorr = Measurement(value: meanObliqDeg + 0.00256 * cos(omega), unit: UnitAngle.degrees)

    // Solar Declination
    let sinDecl = min(1.0, max(-1.0, sin(obliqCorr) * sin(apparentLong)))
    let declination = asinAngle(sinDecl)

    // Equation of Time (minutes)
    let halfObliq = Measurement(value: obliqCorr.value / 2.0, unit: UnitAngle.degrees)
    let tanHalfObliq = tan(halfObliq)
    let y = tanHalfObliq * tanHalfObliq

    let twoL0 = Measurement(value: 2.0 * l0.value, unit: UnitAngle.degrees)
    let fourL0 = Measurement(value: 4.0 * l0.value, unit: UnitAngle.degrees)

    let eqTimeRadians = y * sin(twoL0)
      - 2.0 * e * sin(m)
      + 4.0 * e * y * sin(m) * cos(twoL0)
      - 0.5 * y * y * sin(fourL0)
      - 1.25 * e * e * sin(m2)
    let eqTimeAngle = Measurement(value: eqTimeRadians, unit: UnitAngle.radians)
    let equationOfTimeMinutes = minutesPerDegree * eqTimeAngle.converted(to: .degrees).value

    return SolarParameters(
      declination: declination,
      equationOfTimeMinutes: equationOfTimeMinutes
    )
  }

  private static func solarElevationAtNoon(
    latitude: Measurement<UnitAngle>,
    declination: Measurement<UnitAngle>
  ) -> Measurement<UnitAngle> {
    let sinElev = sin(latitude) * sin(declination) + cos(latitude) * cos(declination)
    return asinAngle(min(1.0, max(-1.0, sinElev)))
  }

  private static func hourAngle(
    latitude: Measurement<UnitAngle>,
    declination: Measurement<UnitAngle>,
    targetElevation: Measurement<UnitAngle>,
    solarNoonElevation: Measurement<UnitAngle>
  ) -> HourAngleResult {
    let denominator = cos(latitude) * cos(declination)
    guard abs(denominator) > 1e-12 else {
      return solarNoonElevation >= targetElevation ? .alwaysAbove : .alwaysBelow
    }

    let cosH = (sin(targetElevation) - sin(latitude) * sin(declination)) / denominator

    if cosH < -1.0 {
      return .alwaysAbove
    }
    if cosH > 1.0 {
      return .alwaysBelow
    }
    return .angle(acosAngle(cosH))
  }

  // MARK: - Measurement Trigonometry Helpers

  private static func sin(_ angle: Measurement<UnitAngle>) -> Double {
    Foundation.sin(angle.converted(to: .radians).value)
  }

  private static func cos(_ angle: Measurement<UnitAngle>) -> Double {
    Foundation.cos(angle.converted(to: .radians).value)
  }

  private static func tan(_ angle: Measurement<UnitAngle>) -> Double {
    Foundation.tan(angle.converted(to: .radians).value)
  }

  private static func asinAngle(_ value: Double) -> Measurement<UnitAngle> {
    Measurement(value: Foundation.asin(value), unit: UnitAngle.radians).converted(to: .degrees)
  }

  private static func acosAngle(_ value: Double) -> Measurement<UnitAngle> {
    Measurement(value: Foundation.acos(value), unit: UnitAngle.radians).converted(to: .degrees)
  }
}
