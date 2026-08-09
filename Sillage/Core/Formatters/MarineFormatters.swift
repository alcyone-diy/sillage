//
//  MarineFormatters.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public struct MarineFormatters {
  /// The global boundary threshold (0.1 NM / 185.2 meters) between short distances
  /// (formatted using iOS system units) and long distances (formatted in nautical miles).
  public static let shortDistanceThreshold = Measurement<UnitLength>(value: 185.2, unit: .meters)

  public static let fileSizeFormatter: MeasurementFormatter = {
    let formatter = MeasurementFormatter()
    formatter.unitOptions = .naturalScale
    formatter.numberFormatter.maximumFractionDigits = 1
    return formatter
  }()
}

extension Duration {
  public var marineFormatted: String {
    return self.formatted(
      .units(
        allowed: [.days, .hours, .minutes],
        width: .abbreviated
      )
    )
  }
}

extension Measurement where UnitType == UnitLength {
  public var marineFormatted: String {
    self.converted(to: .nauticalMiles).formatted(
      .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2)))
    )
  }

  /// Formats a distance measurement for marine contextual displays.
  /// If the distance is below `MarineFormatters.shortDistanceThreshold` (0.1 NM / 185.2m), formats using the user's iOS measurement system settings (meters or feet).
  /// Otherwise, formats in nautical miles (NM).
  ///
  /// - Note: Technical Rationale: To prevent Foundation's `usage: .general` from scaling short distances down to sub-units (centimeters or inches),
  ///   we explicitly inspect `locale.measurementSystem`. If metric, we convert to `.meters`; otherwise (covering `.us` and `.uk`) to `.feet`.
  ///   We then format using `usage: .asProvided` with 0 decimal places, strictly locking the minimum display unit to `m` or `ft`.
  public func marineContextualDistanceFormatted(locale: Locale = .autoupdatingCurrent) -> String {
    if self.converted(to: .meters) < MarineFormatters.shortDistanceThreshold {
      return marineAnchorDistanceFormatted(locale: locale)
    } else {
      return self.converted(to: .nauticalMiles).formatted(
        .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2)))
      )
    }
  }

  /// Technical Design Choice: Dynamic Anchor Distance Formatting
  /// Formats short distance measurements strictly according to the user's measurement system preference.
  /// Maps `.metric` -> `.meters`, and explicitly maps non-metric systems (`.us`, `.uk`) -> `.feet`.
  /// Locks display format to `.asProvided` with 0 decimal places to prevent Foundation from scaling
  /// down to sub-units like centimeters, inches, or yards.
  public func marineAnchorDistanceFormatted(locale: Locale = .autoupdatingCurrent) -> String {
    let isMetric = locale.measurementSystem == .metric
    let targetUnit: UnitLength = isMetric ? .meters : .feet
    return self.converted(to: targetUnit).formatted(
      .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
    )
  }
}

extension Measurement where UnitType == UnitSpeed {
    public var marineFormatted: String {
        self.converted(to: .knots).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))
        )
    }
}

extension Measurement where UnitType == UnitAngle {
  public var marineFormatted: String {
    self.converted(to: .degrees).formatted(
      .measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(6)))
    )
  }
}

extension Measurement where UnitType == UnitArea {
  public var marineFormatted: String {
    self.converted(to: .squareNauticalMiles).formatted(
      .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))
    )
  }
}

extension FormatStyle where Self == Measurement<UnitLength>.FormatStyle {
  /// Standardized format style for anchor distance measurements in meters (e.g. "50 m").
  public static var anchorDistance: Measurement<UnitLength>.FormatStyle {
    .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
  }
}

