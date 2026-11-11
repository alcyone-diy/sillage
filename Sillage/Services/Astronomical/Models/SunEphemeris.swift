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

/// Represents solar ephemeris and nautical twilight times for a given position and date.
public struct SunEphemeris: Sendable, Equatable, Hashable {
  public let sunrise: Date?
  public let sunset: Date?
  public let nauticalTwilightStart: Date?
  public let nauticalTwilightEnd: Date?

  public init(
    sunrise: Date? = nil,
    sunset: Date? = nil,
    nauticalTwilightStart: Date? = nil,
    nauticalTwilightEnd: Date? = nil
  ) {
    self.sunrise = sunrise
    self.sunset = sunset
    self.nauticalTwilightStart = nauticalTwilightStart
    self.nauticalTwilightEnd = nauticalTwilightEnd
  }
}
