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
  var marineFormatted: String {
    self.converted(to: .nauticalMiles).formatted(
      .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2)))
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
