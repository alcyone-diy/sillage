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
  // courseOverGround and courseOverGroundAccuracy both valid or none.
  public let courseOverGround: Measurement<UnitAngle>?
  public let courseOverGroundAccuracy: Measurement<UnitAngle>?
  // speedOverGround and speedOverGroundAccuracy both valid or none.
  public let speedOverGround: Measurement<UnitSpeed>?
  public let speedOverGroundAccuracy: Measurement<UnitSpeed>?

  // Always valid.
  public let timestamp: Date

  public init(
    coordinate: CLLocationCoordinate2D,
    horizontalAccuracy: Measurement<UnitLength>,
    courseOverGround: Measurement<UnitAngle>?,
    courseOverGroundAccuracy: Measurement<UnitAngle>?,
    speedOverGround: Measurement<UnitSpeed>?,
    speedOverGroundAccuracy: Measurement<UnitSpeed>?,
    timestamp: Date
  ) {
    self.coordinate = coordinate
    self.horizontalAccuracy = horizontalAccuracy
    self.courseOverGround = courseOverGround
    self.courseOverGroundAccuracy = courseOverGroundAccuracy
    self.speedOverGround = speedOverGround
    self.speedOverGroundAccuracy = speedOverGroundAccuracy
    self.timestamp = timestamp
  }

  /// Calculates the geodesic distance on the WGS-84 reference ellipsoid via `NavigationMath`
  /// without allocating Objective-C `CLLocation` instances.
  nonisolated public func distance(from navigationFix: NavigationFix) -> Measurement<UnitLength> {
    return self.coordinate.distance(to: navigationFix.coordinate)
  }

  /// Explicit Equatable implementation.
  /// A fix is considered identical if it occurs at the exact same geographic point and time.
  nonisolated public static func == (lhs: NavigationFix, rhs: NavigationFix) -> Bool {
    return lhs.coordinate.latitude == rhs.coordinate.latitude &&
      lhs.coordinate.longitude == rhs.coordinate.longitude &&
      lhs.timestamp == rhs.timestamp
  }
}
