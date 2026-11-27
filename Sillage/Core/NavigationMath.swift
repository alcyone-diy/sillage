//
//  NavigationMath.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

// MARK: - Geodesic & Spherical Navigation Math
//
// Architectural Decision (Ellipsoid vs. Sphere):
// 1. Point-to-point surface distances (`distance(to:)`, `geodesicDistance(to:)`) use Vincenty's
//    inverse formula on the WGS-84 reference ellipsoid (~0.5 mm precision), falling back to
//    spherical Haversine strictly when iterative convergence fails near exact antipodes.
// 2. Chart-space projections, bearings, and Cross-Track Error (`circularPolygon`,
//    `greatCircleCoordinate`, `rhumbCoordinate`, `greatCircleBearing`, `crossTrackError`)
//    intentionally use the spherical / loxodromic Earth model (`GeodesicConstants.earthMeanRadius`)
//    to stay geometrically consistent with Web Mercator map rendering and spherical trigonometry.

extension CLLocationCoordinate2D {

  private nonisolated static let earthRadius = GeodesicConstants.earthMeanRadius
  private nonisolated static let vincentyMaxIterations = 200
  private nonisolated static let vincentyConvergenceTolerance = 1e-12

  // MARK: - WGS-84 Ellipsoidal Distance (Vincenty Inverse)

  /// Calculates the geodesic surface distance to `destination` on the WGS-84 reference ellipsoid
  /// using Vincenty's inverse formula, returning `nil` if either coordinate is non-finite or out of geographic bounds.
  nonisolated public func geodesicDistance(to destination: CLLocationCoordinate2D) -> Measurement<UnitLength>? {
    guard self.latitude.isFinite,
          self.longitude.isFinite,
          destination.latitude.isFinite,
          destination.longitude.isFinite,
          abs(self.latitude) <= 90.0,
          abs(destination.latitude) <= 90.0,
          abs(self.longitude) <= 180.0,
          abs(destination.longitude) <= 180.0 else {
      return nil
    }
    return vincentyOrHaversineDistance(to: destination)
  }

  /// Calculates the geodesic surface distance to `destination` on the WGS-84 reference ellipsoid
  /// using Vincenty's inverse formula (with spherical Haversine fallback for near-antipodal pairs).
  /// Delegates directly to `geodesicDistance(to:)` without clamping out-of-bounds coordinates;
  /// returns `.nan` meters when either coordinate is non-finite or outside geographic bounds (`[-90, 90]` / `[-180, 180]`).
  nonisolated public func distance(to destination: CLLocationCoordinate2D) -> Measurement<UnitLength> {
    return geodesicDistance(to: destination) ?? Measurement(value: .nan, unit: .meters)
  }

  private nonisolated func vincentyOrHaversineDistance(to destination: CLLocationCoordinate2D) -> Measurement<UnitLength> {
    let rawDeltaLonDeg = (destination.longitude - self.longitude).truncatingRemainder(dividingBy: 360.0)
    let normalizedDeltaLonDeg: Double
    if rawDeltaLonDeg > 180.0 {
      normalizedDeltaLonDeg = rawDeltaLonDeg - 360.0
    } else if rawDeltaLonDeg < -180.0 {
      normalizedDeltaLonDeg = rawDeltaLonDeg + 360.0
    } else {
      normalizedDeltaLonDeg = rawDeltaLonDeg
    }

    // Fast-path identical coordinates (including ±180° anti-meridian alias and identical poles)
    if self.latitude == destination.latitude && (normalizedDeltaLonDeg == 0.0 || abs(self.latitude) == 90.0) {
      return Measurement(value: 0.0, unit: .meters)
    }

    let a = GeodesicConstants.WGS84.semiMajorAxis.converted(to: .meters).value
    let f = GeodesicConstants.WGS84.flattening
    let b = GeodesicConstants.WGS84.semiMinorAxis.converted(to: .meters).value

    let (sinU1, cosU1) = Self.reducedLatitudeTrig(latitudeDegrees: self.latitude, flattening: f)
    let (sinU2, cosU2) = Self.reducedLatitudeTrig(latitudeDegrees: destination.latitude, flattening: f)
    let deltaLonRad = Measurement(value: normalizedDeltaLonDeg, unit: UnitAngle.degrees)
      .converted(to: .radians).value

    var lambda = deltaLonRad
    var sinSigma = 0.0
    var cosSigma = 0.0
    var sigma = 0.0
    var cos2Alpha = 0.0
    var cos2SigmaM = 0.0
    var converged = false

    for _ in 0..<Self.vincentyMaxIterations {
      let sinLambda = sin(lambda)
      let cosLambda = cos(lambda)

      let term1 = cosU2 * sinLambda
      let term2 = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda
      sinSigma = hypot(term1, term2)
      cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda

      if sinSigma == 0.0 {
        if cosSigma >= 0.0 {
          return Measurement(value: 0.0, unit: .meters)
        } else {
          // Exact antipodal singularity; fall back to spherical Haversine.
          break
        }
      }

      sigma = atan2(sinSigma, cosSigma)
      let sinAlpha = (cosU1 * cosU2 * sinLambda) / sinSigma
      cos2Alpha = max(0.0, 1.0 - sinAlpha * sinAlpha)

      if cos2Alpha <= 1e-12 {
        // Equatorial geodesic: sigma1 is indeterminate, Vincenty defines cos(2*sigma_m) = 0.
        cos2SigmaM = 0.0
      } else {
        cos2SigmaM = cosSigma - (2.0 * sinU1 * sinU2) / cos2Alpha
      }

      let c = (f / 16.0) * cos2Alpha * (4.0 + f * (4.0 - 3.0 * cos2Alpha))
      let lambdaPrev = lambda
      let cos2SigmaMSq = cos2SigmaM * cos2SigmaM
      lambda = deltaLonRad + (1.0 - c) * f * sinAlpha * (
        sigma + c * sinSigma * (cos2SigmaM + c * cosSigma * (-1.0 + 2.0 * cos2SigmaMSq))
      )

      if !lambda.isFinite {
        break
      }

      if abs(lambda - lambdaPrev) <= Self.vincentyConvergenceTolerance {
        converged = true
        break
      }
    }

    guard converged else {
      return haversineDistance(to: destination)
    }

    let uSquared = cos2Alpha * ((a * a - b * b) / (b * b))
    let coeffA = 1.0 + (uSquared / 16384.0) * (4096.0 + uSquared * (-768.0 + uSquared * (320.0 - 175.0 * uSquared)))
    let coeffB = (uSquared / 1024.0) * (256.0 + uSquared * (-128.0 + uSquared * (74.0 - 47.0 * uSquared)))
    let cos2SigmaMSq = cos2SigmaM * cos2SigmaM
    let sinSigmaSq = sinSigma * sinSigma
    let deltaSigma = coeffB * sinSigma * (
      cos2SigmaM + (coeffB / 4.0) * (
        cosSigma * (-1.0 + 2.0 * cos2SigmaMSq) -
        (coeffB / 6.0) * cos2SigmaM * (-3.0 + 4.0 * sinSigmaSq) * (-3.0 + 4.0 * cos2SigmaMSq)
      )
    )

    let distanceMeters = b * coeffA * (sigma - deltaSigma)
    guard distanceMeters.isFinite, distanceMeters >= 0.0 else {
      return haversineDistance(to: destination)
    }
    return Measurement(value: distanceMeters, unit: .meters)
  }

  private nonisolated static func reducedLatitudeTrig(
    latitudeDegrees: Double,
    flattening: Double
  ) -> (sinU: Double, cosU: Double) {
    if latitudeDegrees >= 90.0 {
      return (1.0, 0.0)
    }
    if latitudeDegrees <= -90.0 {
      return (-1.0, 0.0)
    }
    let phi = Measurement(value: latitudeDegrees, unit: UnitAngle.degrees).converted(to: .radians).value
    let tanU = (1.0 - flattening) * tan(phi)
    let cosU = 1.0 / hypot(1.0, tanU)
    let sinU = tanU * cosU
    return (sinU, cosU)
  }

  /// Spherical central angle in radians via Haversine, shared by spherical fallback and `crossTrackError`.
  private nonisolated func sphericalAngularDistanceRadians(to destination: CLLocationCoordinate2D) -> Double {
    let lat1 = Measurement(value: self.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let lon1 = Measurement(value: self.longitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let lat2 = Measurement(value: destination.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let lon2 = Measurement(value: destination.longitude, unit: UnitAngle.degrees).converted(to: .radians).value

    let dLat = lat2 - lat1
    let dLon = lon2 - lon1

    let rawA = sin(dLat / 2.0) * sin(dLat / 2.0) + cos(lat1) * cos(lat2) * sin(dLon / 2.0) * sin(dLon / 2.0)
    let clampedA = min(1.0, max(0.0, rawA))
    return 2.0 * atan2(sqrt(clampedA), sqrt(1.0 - clampedA))
  }

  /// Spherical Great Circle distance fallback (`earthMeanRadius = 6,371,000 m`).
  nonisolated func haversineDistance(to destination: CLLocationCoordinate2D) -> Measurement<UnitLength> {
    let centralAngle = sphericalAngularDistanceRadians(to: destination)
    let distanceMeters = Self.earthRadius.converted(to: .meters).value * centralAngle
    return Measurement(value: distanceMeters, unit: .meters)
  }

  // MARK: - Spherical & Loxodromic Projections (Chart / Web Mercator Space)

  /// Generates a mathematically closed polygon (circle) of coordinates representing a radius around a center point
  /// using the spherical Earth model (`GeodesicConstants.earthMeanRadius`).
  /// - Parameter radius: The physical radius as a `Measurement<UnitLength>`.
  /// - Returns: An array of 65 coordinates (64 points + 1 closing point) forming the polygon.
  nonisolated func circularPolygon(radius: Measurement<UnitLength>) -> [CLLocationCoordinate2D]? {
    let radiusInMeters = radius.converted(to: .meters).value
    guard radiusInMeters.isFinite, radiusInMeters > 0 else { return nil }

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

  /// Projects a coordinate given a distance and bearing using the spherical Great Circle model.
  /// - Parameters:
  ///   - distance: Distance as a `Measurement<UnitLength>`.
  ///   - bearing: The compass bearing as a `Measurement<UnitAngle>` (0 = True North).
  /// - Returns: The projected coordinate, or nil if inputs/outputs are mathematically invalid.
  nonisolated func greatCircleCoordinate(atDistance distance: Measurement<UnitLength>, bearing: Measurement<UnitAngle>) -> CLLocationCoordinate2D? {
    guard distance.value.isFinite, distance.value >= 0, bearing.value.isFinite,
          self.latitude.isFinite, self.longitude.isFinite else { return nil }

    let distanceInMeters = distance.converted(to: .meters).value

    let lat1Radians = Measurement(value: self.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let lon1Radians = Measurement(value: self.longitude, unit: UnitAngle.degrees).converted(to: .radians).value

    let angularDistanceRadians = distanceInMeters / Self.earthRadius.converted(to: .meters).value
    let trueCourseRadians = bearing.converted(to: .radians).value

    let lat2Radians = asin(sin(lat1Radians) * cos(angularDistanceRadians) + cos(lat1Radians) * sin(angularDistanceRadians) * cos(trueCourseRadians))

    let lon2Radians = lon1Radians + atan2(
      sin(trueCourseRadians) * sin(angularDistanceRadians) * cos(lat1Radians),
      cos(angularDistanceRadians) - sin(lat1Radians) * sin(lat2Radians)
    )

    let degreesLon = Measurement(value: lon2Radians, unit: UnitAngle.radians).converted(to: .degrees).value
    let normalizedLonDeg = (degreesLon + 540.0).truncatingRemainder(dividingBy: 360.0) - 180.0

    let lat2Deg = Measurement(value: lat2Radians, unit: UnitAngle.radians).converted(to: .degrees).value

    guard lat2Deg.isFinite, normalizedLonDeg.isFinite, lat2Deg >= -90.0, lat2Deg <= 90.0 else { return nil }

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
  nonisolated func rhumbCoordinate(atDistance distance: Measurement<UnitLength>, bearing: Measurement<UnitAngle>) -> CLLocationCoordinate2D? {
    guard distance.value.isFinite, distance.value >= 0, bearing.value.isFinite,
          self.latitude.isFinite, self.longitude.isFinite else { return nil }

    let distanceInMeters = distance.converted(to: .meters).value

    let lat1Radians = Measurement(value: self.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let lon1Radians = Measurement(value: self.longitude, unit: UnitAngle.degrees).converted(to: .radians).value

    let angularDistanceRadians = distanceInMeters / Self.earthRadius.converted(to: .meters).value
    let trueCourseRadians = bearing.converted(to: .radians).value

    let lat2Radians = lat1Radians + angularDistanceRadians * cos(trueCourseRadians)

    var lat2Deg = Measurement(value: lat2Radians, unit: UnitAngle.radians).converted(to: .degrees).value
    // Clamp latitude to avoid division by zero (infinity) at the poles in Mercator projections
    if lat2Deg > 89.9 { lat2Deg = 89.9 }
    if lat2Deg < -89.9 { lat2Deg = -89.9 }

    let clampedLat2Radians = Measurement(value: lat2Deg, unit: UnitAngle.degrees).converted(to: .radians).value

    let dPhi = log(tan(.pi / 4.0 + clampedLat2Radians / 2.0) / tan(.pi / 4.0 + lat1Radians / 2.0))

    let q: Double
    if abs(dPhi) > 1e-12 {
      q = (clampedLat2Radians - lat1Radians) / dPhi
    } else {
      q = cos(lat1Radians)
    }

    let dLonRadians = angularDistanceRadians * sin(trueCourseRadians) / q
    let lon2Radians = lon1Radians + dLonRadians

    let degreesLon = Measurement(value: lon2Radians, unit: UnitAngle.radians).converted(to: .degrees).value
    let normalizedLonDeg = (degreesLon + 540.0).truncatingRemainder(dividingBy: 360.0) - 180.0

    guard lat2Deg.isFinite, normalizedLonDeg.isFinite, lat2Deg >= -90.0, lat2Deg <= 90.0 else { return nil }

    return CLLocationCoordinate2D(
      latitude: lat2Deg,
      longitude: normalizedLonDeg
    )
  }

  /// Calculates the spherical Great Circle initial bearing from this coordinate to another coordinate.
  /// - Parameter destination: The target coordinate.
  /// - Returns: The compass bearing as a `Measurement<UnitAngle>` (0 = True North).
  nonisolated func greatCircleBearing(to destination: CLLocationCoordinate2D) -> Measurement<UnitAngle>? {
    guard self.latitude.isFinite, self.longitude.isFinite,
          destination.latitude.isFinite, destination.longitude.isFinite else { return nil }
    // Technical Design Choice: Indeterminate bearing to identical position returns nil per maritime navigation principles
    guard self.latitude != destination.latitude || self.longitude != destination.longitude else { return nil }

    let lat1 = Measurement(value: self.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let lon1 = Measurement(value: self.longitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let lat2 = Measurement(value: destination.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let lon2 = Measurement(value: destination.longitude, unit: UnitAngle.degrees).converted(to: .radians).value

    let dLon = lon2 - lon1
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    let bearingRadians = atan2(y, x)

    var bearingDegrees = Measurement(value: bearingRadians, unit: UnitAngle.radians).converted(to: .degrees).value
    bearingDegrees = (bearingDegrees + 360.0).truncatingRemainder(dividingBy: 360.0)

    guard bearingDegrees.isFinite else { return nil }

    return Measurement(value: bearingDegrees, unit: UnitAngle.degrees)
  }

  /// Calculates the spherical Cross Track Error (XTE) from this coordinate to the Great Circle track line
  /// defined by `origin` and `destination`.
  /// - Parameters:
  ///   - origin: The starting coordinate of the leg track line.
  ///   - destination: The target destination coordinate of the leg track line.
  /// - Returns: Physical cross-track error distance as a `Measurement<UnitLength>`, or `nil` if inputs are invalid or `origin == destination`.
  nonisolated func crossTrackError(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> Measurement<UnitLength>? {
    guard self.latitude.isFinite, self.longitude.isFinite,
          let bearingToDestination = origin.greatCircleBearing(to: destination) else {
      return nil
    }

    // Uses spherical angular distance directly so spherical trigonometry is never mixed with WGS-84 ellipsoidal arc lengths.
    let delta13 = origin.sphericalAngularDistanceRadians(to: self)
    guard delta13.isFinite else { return nil }

    guard delta13 > 0,
          let bearingToCurrent = origin.greatCircleBearing(to: self) else {
      return Measurement(value: 0.0, unit: .meters)
    }

    let theta13 = bearingToCurrent.converted(to: .radians).value
    let theta12 = bearingToDestination.converted(to: .radians).value

    let rawSinArg = sin(delta13) * sin(theta13 - theta12)
    let clampedSinArg = min(1.0, max(-1.0, rawSinArg))
    let crossTrackDistanceRadians = asin(clampedSinArg)
    let crossTrackMeters = crossTrackDistanceRadians * Self.earthRadius.converted(to: .meters).value

    guard crossTrackMeters.isFinite else { return nil }

    return Measurement(value: crossTrackMeters, unit: .meters)
  }
}
