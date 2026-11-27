//
//  GeodesicConstants.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public enum GeodesicConstants {
  /// Standard IUGG mean spherical Earth radius (6,371,000 m) used across spherical and loxodromic projections.
  nonisolated public static let earthMeanRadius = Measurement(value: 6_371_000.0, unit: UnitLength.meters)

  /// WGS-84 reference ellipsoid parameters (NIMA TR8350.2).
  public enum WGS84 {
    /// Equatorial radius (semi-major axis `a`).
    nonisolated public static let semiMajorAxis = Measurement(value: 6_378_137.0, unit: UnitLength.meters)

    /// Reciprocal of flattening (`1 / f`).
    nonisolated public static let inverseFlattening: Double = 298.257223563

    /// Ellipsoidal flattening (`f = 1 / 298.257223563`).
    nonisolated public static let flattening: Double = 1.0 / inverseFlattening

    /// Polar radius (`b = a * (1 - f)`).
    nonisolated public static let semiMinorAxis = Measurement(
      value: semiMajorAxis.value * (1.0 - flattening),
      unit: UnitLength.meters
    )
  }
}
