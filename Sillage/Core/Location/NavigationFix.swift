//
//  NavigationFix.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

public struct NavigationFix: Sendable, Equatable {
  // Always valid.
  public let coordinate: CLLocationCoordinate2D
  // Always valid.
  public let horizontalAccuracy: Measurement<UnitLength>
  // Valid only if courseAccuracy > 0.
  public let course: CLLocationDirection
  public let courseAccuracy: CLLocationDirectionAccuracy
  // Valid only if speedAccuracy > 0.
  public let speed: CLLocationSpeed
  public let speedAccuracy: CLLocationSpeedAccuracy
  // Always valid.
  public let timestamp: Date
  
  /// Calculates the geodetic distance using the WGS 84 reference ellipsoid.
  /// Note: Instantiating CLLocation is necessary here to leverage Apple's highly accurate
  /// underlying GIS algorithms, as a simple Haversine formula is insufficient for marine navigation.
  public func distance(from navigationFix: NavigationFix) -> Double {
    let startLocation = CLLocation(latitude: self.coordinate.latitude, longitude: self.coordinate.longitude)
    let endLocation = CLLocation(latitude: navigationFix.coordinate.latitude, longitude: navigationFix.coordinate.longitude)
    
    let distanceInMeters = startLocation.distance(from: endLocation)
    return distanceInMeters
  }
  
  /// Calculates the initial bearing to another coordinate.
  public func bearing(to location: NavigationFix) -> Measurement<UnitAngle> {
    let lat1 = self.coordinate.latitude * .pi / 180.0
    let lon1 = self.coordinate.longitude * .pi / 180.0
    let lat2 = location.coordinate.latitude * .pi / 180.0
    let lon2 = location.coordinate.longitude * .pi / 180.0
    let dLon = lon2 - lon1
    
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    var bearingRadians = atan2(y, x)
    if bearingRadians < 0 {
      bearingRadians += 2 * .pi
    }
    
    return Measurement(value: bearingRadians, unit: .radians)
  }
  
  /// Explicit Equatable implementation.
  /// A fix is considered identical if it occurs at the exact same geographic point and time.
  public static func == (lhs: NavigationFix, rhs: NavigationFix) -> Bool {
    return lhs.coordinate.latitude == rhs.coordinate.latitude &&
    lhs.coordinate.longitude == rhs.coordinate.longitude &&
    lhs.timestamp == rhs.timestamp
  }
}
