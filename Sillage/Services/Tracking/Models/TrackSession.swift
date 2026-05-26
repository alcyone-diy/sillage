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
  public let duration: Duration?
  public let totalDistance: Measurement<UnitLength>?
  public let southLatitude: Measurement<UnitAngle>?
  public let northLatitude: Measurement<UnitAngle>?
  public let westLongitude: Measurement<UnitAngle>?
  public let eastLongitude: Measurement<UnitAngle>?
  public let maxSpeed: Measurement<UnitSpeed>?
  public let pointsCount: Int?
  public let segmentCount: Int?
  
  public init(
    id: String,
    startTime: Date,
    endTime: Date? = nil,
    name: String? = nil,
    description: String? = nil,
    startLocation: String? = nil,
    endLocation: String? = nil,
    duration: Duration? = nil,
    totalDistance: Measurement<UnitLength>? = nil,
    southLatitude: Measurement<UnitAngle>? = nil,
    northLatitude: Measurement<UnitAngle>? = nil,
    westLongitude: Measurement<UnitAngle>? = nil,
    eastLongitude: Measurement<UnitAngle>? = nil,
    maxSpeed: Measurement<UnitSpeed>? = nil,
    pointsCount: Int? = nil,
    segmentCount: Int? = nil
  ) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.name = name
    self.description = description
    self.startLocation = startLocation
    self.endLocation = endLocation
    self.duration = duration
    self.totalDistance = totalDistance
    self.southLatitude = southLatitude
    self.northLatitude = northLatitude
    self.westLongitude = westLongitude
    self.eastLongitude = eastLongitude
    self.maxSpeed = maxSpeed
    self.pointsCount = pointsCount
    self.segmentCount = segmentCount
  }
  
  public var averageSpeed: Measurement<UnitSpeed>? {
    guard let distance = totalDistance,
          let duration = duration else {
      return nil
    }
    
    let seconds = Double(duration.components.seconds)
    guard seconds > 0 else { return nil }
    
    let speedMps = distance.converted(to: .meters).value / seconds
    return Measurement(value: speedMps, unit: UnitSpeed.metersPerSecond)
  }
}
