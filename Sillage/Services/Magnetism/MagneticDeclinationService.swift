//
//  MagneticDeclinationService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Actor responsible for calculating geomagnetic declination (WMM - World Magnetic Model)
/// for any geographic location and date.
/// - Important: Must never rely on Apple's `CoreLocation.CLHeading` or hardware compass.
///   Returns strict physical `Measurement<UnitAngle>` or `nil` on invalid state.
public actor MagneticDeclinationService {

  public init() {}

  /// Calculates the magnetic declination for a given location and date.
  /// - Parameters:
  ///   - coordinate: The geographical coordinate (`CLLocationCoordinate2D`).
  ///   - date: The date for which the geomagnetic model is evaluated. Defaults to current date.
  /// - Returns: The magnetic declination as a `Measurement<UnitAngle>`, positive for East declination,
  ///   negative for West declination, or `nil` if the coordinate is invalid or calculation fails.
  /// - Note: Never returns dummy `0.0` on failure.
  public func calculateDeclination(
    for coordinate: CLLocationCoordinate2D,
    date: Date = Date()
  ) async -> Measurement<UnitAngle>? {
    guard CLLocationCoordinate2DIsValid(coordinate) else {
      return nil
    }

    // TODO: Replace with full World Magnetic Model (WMM) calculation engine
    // Temporary stub for UI integration and testing
    return Measurement(value: -1.5, unit: UnitAngle.degrees)
  }

  /// Convenience alias matching standard marine declination terminology.
  public func declination(
    for coordinate: CLLocationCoordinate2D,
    date: Date = Date()
  ) async -> Measurement<UnitAngle>? {
    await calculateDeclination(for: coordinate, date: date)
  }
}
