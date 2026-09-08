//
//  WeatherAlarmLevel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Represents a mutually exclusive weather alarm level based on barometric trends.
/// Technical Design Choice: Absence of an active alarm is strictly modeled as `nil` (Optional),
/// adhering to DDD and Zero Dummy Value standards (no dummy `.none` or empty string states).
public enum WeatherAlarmLevel: Sendable, Equatable {
  case vigilance // Drop >= 1.5 hPa / 3h
  case gale      // Drop >= 3.0 hPa / 3h
  case storm     // Drop >= 5.0 hPa / 3h
  case squall    // Rapid short drop (e.g., >= 2.0 hPa / 1h)
  
  public var localizedName: String {
    switch self {
    case .vigilance: return String(localized: "Vigilance", comment: "Weather alarm")
    case .gale: return String(localized: "Gale Warning", comment: "Weather alarm")
    case .storm: return String(localized: "Storm Warning", comment: "Weather alarm")
    case .squall: return String(localized: "Squall Imminent", comment: "Weather alarm")
    }
  }
}
