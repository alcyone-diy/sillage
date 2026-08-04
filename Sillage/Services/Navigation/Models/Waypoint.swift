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
import CoreLocation

/// Domain model representing a Waypoint in the Navigation system.
public struct Waypoint: Identifiable, Sendable, Equatable {
  public static let defaultColorHex = "#007AFF"
  
  public let id: String
  public let name: String
  public let description: String?
  public let symbol: String?
  public let colorHex: String?
  public let isVisible: Bool
  
  public let coordinate: CLLocationCoordinate2D
  public let timestamp: Date
  
  public init(
    id: String = UUID().uuidString,
    name: String,
    description: String? = nil,
    symbol: String? = nil,
    colorHex: String? = nil,
    isVisible: Bool = true,
    coordinate: CLLocationCoordinate2D,
    timestamp: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.symbol = symbol
    self.colorHex = colorHex
    self.isVisible = isVisible
    self.coordinate = coordinate
    self.timestamp = timestamp
  }
}
