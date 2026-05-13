//
//  TrackFilters.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-13.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Configuration for location filtering and noise reduction.
public struct TrackFilters: Sendable {
  public let minDistance: Measurement<UnitLength>
  public let minTimeInterval: Measurement<UnitDuration>
  public let maxHorizontalAccuracy: Measurement<UnitLength>

  // Pre-calculated variables to avoid CPU overhead in the high-frequency filtering loop
  public let minDistanceMeters: Double
  public let minTimeIntervalSeconds: Double
  public let maxHorizontalAccuracyMeters: Double

  public init(
    minDistance: Measurement<UnitLength>,
    minTimeInterval: Measurement<UnitDuration>,
    maxHorizontalAccuracy: Measurement<UnitLength>
  ) {
    self.minDistance = minDistance
    self.minTimeInterval = minTimeInterval
    self.maxHorizontalAccuracy = maxHorizontalAccuracy
    
    self.minDistanceMeters = minDistance.converted(to: .meters).value
    self.minTimeIntervalSeconds = minTimeInterval.converted(to: .seconds).value
    self.maxHorizontalAccuracyMeters = maxHorizontalAccuracy.converted(to: .meters).value
  }

  nonisolated public static let `default` = TrackFilters(
    minDistance: Measurement(value: 3.0, unit: UnitLength.meters),
    minTimeInterval: Measurement(value: 60.0, unit: UnitDuration.seconds),
    maxHorizontalAccuracy: Measurement(value: 50.0, unit: UnitLength.meters)
  )
}
