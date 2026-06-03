//
//  Waypoint.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Domain model representing a Waypoint in the Navigation system.
public struct Waypoint: Identifiable, Sendable, Equatable {
  public let id: String
  public let name: String
  public let description: String?
  public let symbol: String?
  
  public let latitude: Measurement<UnitAngle>
  public let longitude: Measurement<UnitAngle>
  public let timestamp: Date
  
  public init(
    id: String = UUID().uuidString,
    name: String,
    description: String? = nil,
    symbol: String? = nil,
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>,
    timestamp: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.symbol = symbol
    self.latitude = latitude
    self.longitude = longitude
    self.timestamp = timestamp
  }
}
