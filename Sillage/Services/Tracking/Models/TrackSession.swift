//
//  TrackSession.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// A representation of a recorded track session.
public struct TrackSession: Sendable, Codable, Identifiable {
  public let id: String
  public let startTime: Date
  public let endTime: Date?
  public let name: String?
  public let description: String?
  public let startLocation: String?
  public let endLocation: String?
  public let totalDuration: Duration?
  public let totalDistanceOverGround: Measurement<UnitLength>?
  public let boundingBox: GeographicBoundingBox?
  public let maxSpeedOverGround: Measurement<UnitSpeed>?
  public let segmentCount: Int
  public let totalPointCount: Int
  public let colorHex: String?

  public init(
    id: String,
    startTime: Date,
    endTime: Date? = nil,
    name: String? = nil,
    description: String? = nil,
    startLocation: String? = nil,
    endLocation: String? = nil,
    totalDuration: Duration? = nil,
    totalDistanceOverGround: Measurement<UnitLength>? = nil,
    boundingBox: GeographicBoundingBox? = nil,
    maxSpeedOverGround: Measurement<UnitSpeed>? = nil,
    segmentCount: Int = 0,
    totalPointCount: Int = 0,
    colorHex: String? = nil
  ) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.name = name
    self.description = description
    self.startLocation = startLocation
    self.endLocation = endLocation
    self.totalDuration = totalDuration
    self.totalDistanceOverGround = totalDistanceOverGround
    self.boundingBox = boundingBox
    self.maxSpeedOverGround = maxSpeedOverGround
    self.segmentCount = segmentCount
    self.totalPointCount = totalPointCount
    self.colorHex = colorHex
  }
  
  public var totalAverageSpeedOverGround: Measurement<UnitSpeed>? {
    guard let totalDistanceOverGround = totalDistanceOverGround,
          let totalDuration = totalDuration else {
      return nil
    }
    
    let seconds = Double(totalDuration.components.seconds)
    guard seconds > 0 else { return nil }
    
    let speedOverGroundMps = totalDistanceOverGround.converted(to: .meters).value / seconds
    return Measurement(value: speedOverGroundMps, unit: UnitSpeed.metersPerSecond)
  }
}
