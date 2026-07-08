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
  
  // MARK: - Private Math
  
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
