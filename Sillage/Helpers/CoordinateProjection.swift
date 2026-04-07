//
//  CoordinateProjection.swift
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
  func coordinate(at distance: CLLocationDistance, bearing: CLLocationDirection) -> CLLocationCoordinate2D {
    let earthRadius = 6371000.0 // meters

    let lat1 = self.latitude * .pi / 180.0
    let lon1 = self.longitude * .pi / 180.0

    let angularDistance = distance / earthRadius
    let trueCourse = bearing * .pi / 180.0

    let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(trueCourse))

    let lon2 = lon1 + atan2(sin(trueCourse) * sin(angularDistance) * cos(lat1), cos(angularDistance) - sin(lat1) * sin(lat2))

    return CLLocationCoordinate2D(
      latitude: lat2 * 180.0 / .pi,
      longitude: (lon2 * 180.0 / .pi).truncatingRemainder(dividingBy: 360.0) // Normalize
    )
  }
}
