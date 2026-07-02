//
//  PressureDropCalculator.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public struct PressureDropCalculator {
  
  /// Calculates the absolute maximum pressure drop that occurred within the provided readings.
  /// This strictly compares the most recent reading against the highest peak observed in the dataset.
  ///
  /// - Parameter readings: Historical barometric readings.
  /// - Returns: A `Measurement<UnitPressure>` representing the drop (a negative value if the pressure has dropped), or nil if data is insufficient.
  public static func calculateMaxDrop(from readings: [BarometricReading]) -> Measurement<UnitPressure>? {
    guard readings.count >= 2 else { return nil }
    
    // Ensure chronological order
    let sortedReadings = readings.sorted { $0.timestamp < $1.timestamp }
    
    guard let currentReading = sortedReadings.last else { return nil }
    guard let peakReading = sortedReadings.max(by: { $0.pressure.value < $1.pressure.value }) else { return nil }
    
    // The drop is the difference between the current (latest) reading and the peak reading
    // If current is lower than peak, this value will be negative.
    // If current IS the peak, this value will be 0.
    return currentReading.pressure - peakReading.pressure
  }
}
