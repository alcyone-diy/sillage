//
//  HeadingVectorPredictor.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-24.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Holds the geospatial data representing a predicted heading vector and its time ticks.
public struct HeadingVectorData: Equatable, Sendable {
  public let lineCoordinates: [CLLocationCoordinate2D]
  public let majorTickCoordinates: [CLLocationCoordinate2D]
  public let minorTickCoordinates: [CLLocationCoordinate2D]
}

/// A Domain-Driven pure function service responsible for generating geospatial predictions
/// based on navigation telemetry (SOG/COG), decoupling the heavy math from the ViewModels.
public struct HeadingVectorPredictor: Sendable {
  
  /// Predicts the vessel's future path based on current speed and course.
  /// - Parameters:
  ///   - startCoordinate: The vessel's current position.
  ///   - sog: Speed Over Ground.
  ///   - cog: Course Over Ground.
  ///   - timeHorizonSeconds: The predictive time horizon in seconds.
  ///   - generateTicks: Whether to generate coordinate ticks for time intervals.
  /// - Returns: A `HeadingVectorData` struct containing the computed coordinates, or nil if invalid/too slow.
  public static func predict(
    startCoordinate: CLLocationCoordinate2D,
    sog: Measurement<UnitSpeed>,
    cog: Measurement<UnitAngle>,
    timeHorizonSeconds: Double,
    generateTicks: Bool
  ) -> HeadingVectorData? {
    let sogKnots = sog.converted(to: .knots).value
    
    // Cut-off below 0.5 knots to avoid erratic spinning vectors when nearly stationary
    if sogKnots < 0.5 { return nil }
    
    let speedInMps = sog.converted(to: .metersPerSecond).value
    let totalDistanceMeters = speedInMps * timeHorizonSeconds
    let totalDistance = Measurement<UnitLength>(value: totalDistanceMeters, unit: .meters)
    
    guard let endCoordinate = startCoordinate.rhumbCoordinate(atDistance: totalDistance, bearing: cog) else {
      return nil
    }
    
    let lineCoords = [startCoordinate, endCoordinate]
    var majorTicks: [CLLocationCoordinate2D] = []
    var minorTicks: [CLLocationCoordinate2D] = []
    
    if generateTicks {
      let intervalSeconds: Double = timeHorizonSeconds <= 3600 ? 600 : 1800
      let majorIntervalSeconds: Double = timeHorizonSeconds <= 3600 ? 1800 : 3600
      var currentTickSeconds = intervalSeconds
      
      while currentTickSeconds < timeHorizonSeconds {
        let tickDistanceMeters = speedInMps * currentTickSeconds
        let tickDistance = Measurement<UnitLength>(value: tickDistanceMeters, unit: .meters)
        
        if let tickCoord = startCoordinate.rhumbCoordinate(atDistance: tickDistance, bearing: cog) {
          let isMajor = currentTickSeconds.truncatingRemainder(dividingBy: majorIntervalSeconds) == 0
          if isMajor {
            majorTicks.append(tickCoord)
          } else {
            minorTicks.append(tickCoord)
          }
        }
        currentTickSeconds += intervalSeconds
      }
      
      // Always mark the end of the vector as a major tick
      majorTicks.append(endCoordinate)
    }
    
    return HeadingVectorData(
      lineCoordinates: lineCoords,
      majorTickCoordinates: majorTicks,
      minorTickCoordinates: minorTicks
    )
  }
}
