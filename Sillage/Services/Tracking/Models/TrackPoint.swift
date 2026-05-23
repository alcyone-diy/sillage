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

/// The in-memory domain representation of a recorded track point.
public struct TrackPoint: Sendable {
  public let timestamp: Date
  public let segmentIndex: Int
  public let latitude: Measurement<UnitAngle>
  public let longitude: Measurement<UnitAngle>
  public let horizontalAccuracy: Measurement<UnitLength>
  public let speedOverGround: Measurement<UnitSpeed>?
  public let courseOverGround: Measurement<UnitAngle>?

  public init(
    timestamp: Date,
    segmentIndex: Int,
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>,
    horizontalAccuracy: Measurement<UnitLength>,
    speedOverGround: Measurement<UnitSpeed>? = nil,
    courseOverGround: Measurement<UnitAngle>? = nil
  ) {
    self.timestamp = timestamp
    self.segmentIndex = segmentIndex
    self.latitude = latitude
    self.longitude = longitude
    self.horizontalAccuracy = horizontalAccuracy
    self.speedOverGround = speedOverGround
    self.courseOverGround = courseOverGround
  }
}
