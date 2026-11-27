//
//  SunEphemeris.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Represents the solar horizon daylight cycle (-0.833° solar elevation, accounting for solar disk radius and standard refraction).
nonisolated public enum SolarDaylightState: Sendable, Equatable, Hashable {
  /// Standard day/night cycle with a sunrise before and sunset after local solar noon.
  case cycle(sunrise: Date, sunset: Date)
  /// Sun remains above the horizon (-0.833°) throughout the solar day (midnight sun).
  case polarDay
  /// Sun remains below the horizon (-0.833°) throughout the solar day.
  case polarNight
}

/// Represents the nautical twilight band (-12.0° solar elevation).
nonisolated public enum NauticalTwilightState: Sendable, Equatable, Hashable {
  /// Standard nautical twilight cycle with a dawn before and dusk after local solar noon.
  case cycle(dawn: Date, dusk: Date)
  /// Sun never drops below -12.0° (white nights / no nautical night).
  case continuousTwilight
  /// Sun never rises above -12.0° (continuous nautical darkness).
  case continuousDark
}

/// Represents solar ephemeris and nautical twilight states for a given position and calendar day.
nonisolated public struct SunEphemeris: Sendable, Equatable, Hashable {
  public let daylight: SolarDaylightState
  public let nauticalTwilight: NauticalTwilightState
  public let solarNoon: Date
  public let solarNoonElevation: Measurement<UnitAngle>
  public let referenceDate: Date
  public let timeZone: TimeZone

  public nonisolated init(
    daylight: SolarDaylightState,
    nauticalTwilight: NauticalTwilightState,
    solarNoon: Date,
    solarNoonElevation: Measurement<UnitAngle>,
    referenceDate: Date,
    timeZone: TimeZone
  ) {
    self.daylight = daylight
    self.nauticalTwilight = nauticalTwilight
    self.solarNoon = solarNoon
    self.solarNoonElevation = solarNoonElevation
    self.referenceDate = referenceDate
    self.timeZone = timeZone
  }
}
