//
//  BarometricReading.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public struct BarometricReading: Codable, Sendable, Equatable {
  public let timestamp: Date
  public let pressure: Measurement<UnitPressure>
  
  public init(timestamp: Date, pressure: Measurement<UnitPressure>) {
    self.timestamp = timestamp
    // The internal unit is strictly .hectopascals
    self.pressure = pressure.converted(to: .hectopascals)
  }
}
