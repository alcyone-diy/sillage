//
//  LinearRegressionCalculator.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public struct LinearRegressionCalculator {
  
  /// Calculates the pressure trend using linear regression.
  /// - Parameters:
  ///   - readings: Historical barometric readings.
  ///   - duration: The duration over which to project the trend.
  /// - Returns: The projected pressure change over the given duration, or nil if data is insufficient.
  public static func calculateTrend(
    from readings: [BarometricReading],
    over duration: TimeInterval
  ) -> Measurement<UnitPressure>? {
    guard readings.count >= 2 else {
      return nil
    }
    
    // Ensure chronological order
    let sortedReadings = readings.sorted { $0.timestamp < $1.timestamp }
    
    guard let first = sortedReadings.first, let last = sortedReadings.last else {
      return nil
    }
    
    let timeSpan = last.timestamp.timeIntervalSince(first.timestamp)
    
    // The temporal gap must be strictly positive to calculate a slope
    guard timeSpan > 0 else {
      return nil
    }
    
    // Ensure the sample covers at least 80% of the target duration
    // to prevent dangerous mathematical extrapolation on short datasets.
    let requiredCoverage = duration * 0.8
    guard timeSpan >= requiredCoverage else {
      return nil
    }
    
    let n = Double(sortedReadings.count)
    let t0 = first.timestamp
    
    var sumX: Double = 0
    var sumY: Double = 0
    var sumXY: Double = 0
    var sumX2: Double = 0
    
    for reading in sortedReadings {
      let x = reading.timestamp.timeIntervalSince(t0)
      let y = reading.pressure.converted(to: .hectopascals).value
      
      sumX += x
      sumY += y
      sumXY += x * y
      sumX2 += x * x
    }
    
    let denominator = (n * sumX2) - (sumX * sumX)
    
    guard denominator != 0 else {
      return nil
    }
    
    // Slope = hPa per second
    let slope = ((n * sumXY) - (sumX * sumY)) / denominator
    
    // Projected change over the duration
    let change = slope * duration
    
    return Measurement(value: change, unit: UnitPressure.hectopascals)
  }
}
