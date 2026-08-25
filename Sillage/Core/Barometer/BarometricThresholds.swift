//
//  BarometricThresholds.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public extension Measurement where UnitType == UnitPressure {
  /// Drop >= 2.0 hPa / 1h (High Sensitivity fast drop)
  static let highFastDropThreshold = Measurement(value: -2.0, unit: UnitPressure.hectopascals)
  
  /// Drop >= 1.5 hPa / 3h
  static let vigilanceThreshold = Measurement(value: -1.5, unit: UnitPressure.hectopascals)
  
  /// Drop >= 3.0 hPa / 3h (Gale Warning)
  static let galeThreshold = Measurement(value: -3.0, unit: UnitPressure.hectopascals)
  
  /// Drop >= 5.0 hPa / 3h (Storm Warning)
  static let stormThreshold = Measurement(value: -5.0, unit: UnitPressure.hectopascals)
  
  /// Minimum plausible atmospheric sea-level pressure (800 hPa)
  static let minimumPlausiblePressure = Measurement(value: 800.0, unit: UnitPressure.hectopascals)
  
  /// Maximum plausible atmospheric sea-level pressure (1100 hPa)
  static let maximumPlausiblePressure = Measurement(value: 1100.0, unit: UnitPressure.hectopascals)
}
