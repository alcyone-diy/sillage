//
//  NavigationMath.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreLocation

extension CLLocationCoordinate2D {

  /// Projects a coordinate given a distance (in meters) and bearing (in degrees) using the Haversine/Vincenty spherical model.
  /// - Parameters:
  ///   - distance: Distance in meters.
  ///   - bearing: Bearing in degrees (0 = North).
  /// - Returns: The projected coordinate.
  func greatCircleCoordinate(atDistance distance: CLLocationDistance, bearing: CLLocationDirection) -> CLLocationCoordinate2D {
    let earthRadius = 6371000.0 // meters

    let lat1 = self.latitude * .pi / 180.0
    let lon1 = self.longitude * .pi / 180.0

    let angularDistance = distance / earthRadius
    let trueCourse = bearing * .pi / 180.0

    let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(trueCourse))

    let lon2 = lon1 + atan2(sin(trueCourse) * sin(angularDistance) * cos(lat1), cos(angularDistance) - sin(lat1) * sin(lat2))

    let degreesLon = lon2 * 180.0 / .pi
    let normalizedLon = (degreesLon + 540.0).truncatingRemainder(dividingBy: 360.0) - 180.0

    return CLLocationCoordinate2D(
      latitude: lat2 * 180.0 / .pi,
      longitude: normalizedLon
    )
  }

  /// Projects a coordinate given a distance (in meters) and bearing (in degrees) using the Rhumb Line (loxodromic) model.
  /// This maintains a constant compass heading, rendering as a straight line on a Mercator projection.
  /// - Parameters:
  ///   - distance: Distance in meters.
  ///   - bearing: Bearing in degrees (0 = North).
  /// - Returns: The projected coordinate.
  func rhumbCoordinate(atDistance distance: CLLocationDistance, bearing: CLLocationDirection) -> CLLocationCoordinate2D {
    let earthRadius = 6371000.0 // meters

    let lat1 = self.latitude * .pi / 180.0
    let lon1 = self.longitude * .pi / 180.0

    let angularDistance = distance / earthRadius
    let trueCourse = bearing * .pi / 180.0

    let lat2 = lat1 + angularDistance * cos(trueCourse)

    var lat2Deg = lat2 * 180.0 / .pi
    // Clamp latitude to avoid division by zero (infinity) at the poles in Mercator projections
    if lat2Deg > 89.9 { lat2Deg = 89.9 }
    if lat2Deg < -89.9 { lat2Deg = -89.9 }

    let clampedLat2 = lat2Deg * .pi / 180.0

    let dPhi = log(tan(.pi / 4.0 + clampedLat2 / 2.0) / tan(.pi / 4.0 + lat1 / 2.0))

    let q: Double
    if abs(dPhi) > 1e-12 {
      q = (clampedLat2 - lat1) / dPhi
    } else {
      q = cos(lat1)
    }

    let dLon = angularDistance * sin(trueCourse) / q
    let lon2 = lon1 + dLon

    let degreesLon = lon2 * 180.0 / .pi
    let normalizedLon = (degreesLon + 540.0).truncatingRemainder(dividingBy: 360.0) - 180.0

    return CLLocationCoordinate2D(
      latitude: lat2Deg,
      longitude: normalizedLon
    )
  }
}
