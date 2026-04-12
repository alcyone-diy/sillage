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

  private static let earthRadius = Measurement<UnitLength>(value: 6371000.0, unit: .meters)

  /// Generates a mathematically closed polygon (circle) of coordinates representing a radius around a center point.
  /// - Parameter radius: The physical radius as a `Measurement<UnitLength>`.
  /// - Returns: An array of 65 coordinates (64 points + 1 closing point) forming the polygon.
  func accuracyPolygon(radius: Measurement<UnitLength>) -> [CLLocationCoordinate2D]? {
    let radiusInMeters = radius.converted(to: .meters).value
    guard radiusInMeters > 0 else { return nil }

    var coordinates = [CLLocationCoordinate2D]()
    coordinates.reserveCapacity(65)

    let numberOfPoints = 64
    let degreeStep = 360.0 / Double(numberOfPoints)

    for i in 0..<numberOfPoints {
      let bearingMeasurement = Measurement<UnitAngle>(value: Double(i) * degreeStep, unit: .degrees)
      if let coordinate = self.greatCircleCoordinate(atDistance: radius, bearing: bearingMeasurement) {
        coordinates.append(coordinate)
      }
    }

    if let first = coordinates.first {
      coordinates.append(first)
    }

    return coordinates
  }

  /// Projects a coordinate given a distance and bearing using the Haversine/Vincenty spherical model.
  /// - Parameters:
  ///   - distance: Distance as a `Measurement<UnitLength>`.
  ///   - bearing: The compass bearing as a `Measurement<UnitAngle>` (0 = True North).
  /// - Returns: The projected coordinate, or nil if inputs/outputs are mathematically invalid.
  func greatCircleCoordinate(atDistance distance: Measurement<UnitLength>, bearing: Measurement<UnitAngle>) -> CLLocationCoordinate2D? {
    guard distance.value >= 0, !bearing.value.isNaN, !bearing.value.isInfinite else { return nil }

    let distanceInMeters = distance.converted(to: .meters).value

    let lat1Radians = self.latitude * .pi / 180.0
    let lon1Radians = self.longitude * .pi / 180.0

    let angularDistanceRadians = distanceInMeters / Self.earthRadius.value
    let trueCourseRadians = bearing.converted(to: .radians).value

    let lat2Radians = asin(sin(lat1Radians) * cos(angularDistanceRadians) + cos(lat1Radians) * sin(angularDistanceRadians) * cos(trueCourseRadians))

    let lon2Radians = lon1Radians + atan2(sin(trueCourseRadians) * sin(angularDistanceRadians) * cos(lat1Radians), cos(angularDistanceRadians) - sin(lat1Radians) * sin(lat2Radians))

    let degreesLon = lon2Radians * 180.0 / .pi
    let normalizedLonDeg = (degreesLon + 540.0).truncatingRemainder(dividingBy: 360.0) - 180.0

    let lat2Deg = lat2Radians * 180.0 / .pi

    guard !lat2Deg.isNaN, !lat2Deg.isInfinite, !normalizedLonDeg.isNaN, !normalizedLonDeg.isInfinite, lat2Deg >= -90.0, lat2Deg <= 90.0 else { return nil }

    return CLLocationCoordinate2D(
      latitude: lat2Deg,
      longitude: normalizedLonDeg
    )
  }

  /// Projects a coordinate given a distance and bearing using the Rhumb Line (loxodromic) model.
  /// This maintains a constant compass heading, rendering as a straight line on a Mercator projection.
  /// - Parameters:
  ///   - distance: Distance as a `Measurement<UnitLength>`.
  ///   - bearing: The compass bearing as a `Measurement<UnitAngle>` (0 = True North).
  /// - Returns: The projected coordinate, or nil if inputs/outputs are mathematically invalid.
  func rhumbCoordinate(atDistance distance: Measurement<UnitLength>, bearing: Measurement<UnitAngle>) -> CLLocationCoordinate2D? {
    guard distance.value >= 0, !bearing.value.isNaN, !bearing.value.isInfinite else { return nil }

    let distanceInMeters = distance.converted(to: .meters).value

    let lat1Radians = self.latitude * .pi / 180.0
    let lon1Radians = self.longitude * .pi / 180.0

    let angularDistanceRadians = distanceInMeters / Self.earthRadius.value
    let trueCourseRadians = bearing.converted(to: .radians).value

    let lat2Radians = lat1Radians + angularDistanceRadians * cos(trueCourseRadians)

    var lat2Deg = lat2Radians * 180.0 / .pi
    // Clamp latitude to avoid division by zero (infinity) at the poles in Mercator projections
    if lat2Deg > 89.9 { lat2Deg = 89.9 }
    if lat2Deg < -89.9 { lat2Deg = -89.9 }

    let clampedLat2Radians = lat2Deg * .pi / 180.0

    let dPhi = log(tan(.pi / 4.0 + clampedLat2Radians / 2.0) / tan(.pi / 4.0 + lat1Radians / 2.0))

    let q: Double
    if abs(dPhi) > 1e-12 {
      q = (clampedLat2Radians - lat1Radians) / dPhi
    } else {
      q = cos(lat1Radians)
    }

    let dLonRadians = angularDistanceRadians * sin(trueCourseRadians) / q
    let lon2Radians = lon1Radians + dLonRadians

    let degreesLon = lon2Radians * 180.0 / .pi
    let normalizedLonDeg = (degreesLon + 540.0).truncatingRemainder(dividingBy: 360.0) - 180.0

    guard !lat2Deg.isNaN, !lat2Deg.isInfinite, !normalizedLonDeg.isNaN, !normalizedLonDeg.isInfinite, lat2Deg >= -90.0, lat2Deg <= 90.0 else { return nil }

    return CLLocationCoordinate2D(
      latitude: lat2Deg,
      longitude: normalizedLonDeg
    )
  }
}
