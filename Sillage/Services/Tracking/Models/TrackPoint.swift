//
//  TrackPoint.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// A representation of a single recorded track point.
public struct TrackPoint: Sendable, Codable {
  public let latitude: Double
  public let longitude: Double
  public let timestamp: Date
  public let sog: Measurement<UnitSpeed>?
  public let cog: Measurement<UnitAngle>?

  public init(latitude: Double, longitude: Double, timestamp: Date, sog: Measurement<UnitSpeed>? = nil, cog: Measurement<UnitAngle>? = nil) {
    self.latitude = latitude
    self.longitude = longitude
    self.timestamp = timestamp
    self.sog = sog
    self.cog = cog
  }
}
