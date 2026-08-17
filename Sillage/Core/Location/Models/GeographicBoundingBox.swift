//
//  GeographicBoundingBox.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

public struct GeographicBoundingBox: Sendable, Equatable, Codable {
  
  // MARK: - Properties
  
  /// (Minimums)
  public private(set) var southWest: CLLocationCoordinate2D
  /// (Maximums)
  public private(set) var northEast: CLLocationCoordinate2D
  
  // MARK: - Initialization
  
  public init(southWest: CLLocationCoordinate2D, northEast: CLLocationCoordinate2D) {
    self.southWest = southWest
    self.northEast = northEast
  }
  
  public init(coordinate: CLLocationCoordinate2D) {
    self.southWest = coordinate
    self.northEast = coordinate
  }
  
  // MARK: - Public
  
  public mutating func expand(toInclude coordinate: CLLocationCoordinate2D) {
    if coordinate.latitude < southWest.latitude { southWest.latitude = coordinate.latitude }
    if coordinate.latitude > northEast.latitude { northEast.latitude = coordinate.latitude }
    
    let isInside: Bool
    if southWest.longitude <= northEast.longitude {
      isInside = (coordinate.longitude >= southWest.longitude) && (coordinate.longitude <= northEast.longitude)
    } else {
      isInside = (coordinate.longitude >= southWest.longitude) || (coordinate.longitude <= northEast.longitude)
    }
    
    if !isInside {
      let expandEast = degreesDistance(from: northEast.longitude, to: coordinate.longitude)
      let expandWest = degreesDistance(from: coordinate.longitude, to: southWest.longitude)
      
      if expandEast < expandWest {
        northEast.longitude = coordinate.longitude
      } else {
        southWest.longitude = coordinate.longitude
      }
    }
  }
  
  // MARK: - Geometry
  
  /// Estimated area (approximation via Haversine for the bounding box)
  public var estimatedArea: Measurement<UnitArea> {
    let heightPoint = CLLocation(latitude: northEast.latitude, longitude: 0)
    let swPoint = CLLocation(latitude: southWest.latitude, longitude: 0)
    let heightMeters = heightPoint.distance(from: swPoint)
    
    let centerLat = (southWest.latitude + northEast.latitude) / 2.0
    let angularWidth = (northEast.longitude - southWest.longitude + 360.0).truncatingRemainder(dividingBy: 360.0)
    let leftPoint = CLLocation(latitude: centerLat, longitude: 0)
    let rightPoint = CLLocation(latitude: centerLat, longitude: angularWidth)
    let widthMeters = leftPoint.distance(from: rightPoint)
    
    return Measurement(value: widthMeters * heightMeters, unit: UnitArea.squareMeters)
  }
  
  /// Compares two bounding boxes with a geographic epsilon tolerance to prevent infinite render loops
  /// caused by floating point precision limits when converting screen rects to map bounds.
  /// 
  /// - Parameters:
  ///   - other: The other `GeographicBoundingBox` to compare against.
  ///   - tolerance: The maximum allowed coordinate deviation (epsilon) in degrees. Defaults to `1e-6`.
  /// - Returns: `true` if all corner coordinates are within the specified tolerance; otherwise `false`.
  public func isApproximatelyEqual(to other: GeographicBoundingBox, tolerance: CLLocationDegrees = 1e-6) -> Bool {
    return abs(southWest.latitude - other.southWest.latitude) < tolerance &&
           shortestLongitudeDelta(from: southWest.longitude, to: other.southWest.longitude) < tolerance &&
           abs(northEast.latitude - other.northEast.latitude) < tolerance &&
           shortestLongitudeDelta(from: northEast.longitude, to: other.northEast.longitude) < tolerance
  }

  /// Generates a standard WKT (Well-Known Text) POLYGON representation of the bounding box
  /// in the format `POLYGON((minLon minLat, maxLon minLat, maxLon maxLat, minLon maxLat, minLon minLat))`.
  public func toWKT() -> String {
    let minLon = southWest.longitude
    let minLat = southWest.latitude
    let maxLon = northEast.longitude
    let maxLat = northEast.latitude
    return "POLYGON((\(minLon) \(minLat), \(maxLon) \(minLat), \(maxLon) \(maxLat), \(minLon) \(maxLat), \(minLon) \(minLat)))"
  }
  
  // MARK: - Private Math
  
  /// Calculates the shortest angular distance between two longitudes, accounting for the 360-degree wrap at the anti-meridian.
  private func shortestLongitudeDelta(from lon1: CLLocationDegrees, to lon2: CLLocationDegrees) -> CLLocationDegrees {
    let delta = abs(lon1 - lon2).truncatingRemainder(dividingBy: 360.0)
    return delta > 180.0 ? 360.0 - delta : delta
  }
  
  private func degreesDistance(from start: CLLocationDegrees, to end: CLLocationDegrees) -> CLLocationDegrees {
    var diff = end - start
    
    while diff < 0.0 {
      diff += 360.0
    }
    while diff >= 360.0 {
      diff -= 360.0
    }
    return diff
  }
}
