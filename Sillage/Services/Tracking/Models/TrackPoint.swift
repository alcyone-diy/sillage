//
//  TrackPoint.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// The in-memory domain representation of a recorded track point.
public struct TrackPoint: Sendable {
  public let timestamp: Date
  public let segmentIndex: Int
  public let coordinate: CLLocationCoordinate2D
  public let horizontalAccuracy: Measurement<UnitLength>
  public let speedOverGround: Measurement<UnitSpeed>?
  public let courseOverGround: Measurement<UnitAngle>?

  public init(
    timestamp: Date,
    segmentIndex: Int,
    coordinate: CLLocationCoordinate2D,
    horizontalAccuracy: Measurement<UnitLength>,
    speedOverGround: Measurement<UnitSpeed>? = nil,
    courseOverGround: Measurement<UnitAngle>? = nil
  ) {
    self.timestamp = timestamp
    self.segmentIndex = segmentIndex
    self.coordinate = coordinate
    self.horizontalAccuracy = horizontalAccuracy
    self.speedOverGround = speedOverGround
    self.courseOverGround = courseOverGround
  }
}
