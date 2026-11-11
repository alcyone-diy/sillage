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
import Solar

/// Actor responsible for astronomical calculations such as solar ephemerides and twilights.
/// - Important: The third-party `Solar` type must remain strictly encapsulated within this actor
///   and must never leak across actor or service boundaries.
public actor AstronomicalService {

  public init() {}

  /// Calculates the solar ephemeris (sunrise, sunset, nautical twilight) for the specified coordinate and date.
  /// - Parameters:
  ///   - coordinate: The geographical coordinate (`CLLocationCoordinate2D`).
  ///   - date: The date for which ephemeris times should be calculated. Defaults to the current date.
  /// - Returns: A `SunEphemeris` containing twilight and rise/set times, or `nil` if the coordinate is invalid.
  public func calculateEphemeris(
    for coordinate: CLLocationCoordinate2D,
    date: Date = Date()
  ) -> SunEphemeris? {
    guard CLLocationCoordinate2DIsValid(coordinate) else {
      return nil
    }

    guard let solar = Solar(for: date, coordinate: coordinate) else {
      return nil
    }

    return SunEphemeris(
      sunrise: solar.sunrise,
      sunset: solar.sunset,
      nauticalTwilightStart: solar.nauticalSunrise,
      nauticalTwilightEnd: solar.nauticalSunset
    )
  }

  /// Convenience method calculating the solar ephemeris.
  public func ephemeris(
    for coordinate: CLLocationCoordinate2D,
    date: Date = Date()
  ) -> SunEphemeris? {
    calculateEphemeris(for: coordinate, date: date)
  }
}
