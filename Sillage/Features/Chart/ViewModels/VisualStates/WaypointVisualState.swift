//
//  WaypointVisualState.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Represents the visual rendering attributes for a waypoint on the chart.
public struct WaypointVisualState: Equatable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let coordinate: CLLocationCoordinate2D
  public let colorHex: String
  
  public init(id: String, name: String, coordinate: CLLocationCoordinate2D, colorHex: String) {
    self.id = id
    self.name = name
    self.coordinate = coordinate
    self.colorHex = colorHex
  }
}

/// Represents the visual coordinates and style for a navigation bearing line to a target waypoint.
public struct BearingLineVisualState: Equatable, Sendable {
  public let coordinates: [CLLocationCoordinate2D]
  public let colorHex: String?
  
  public init(coordinates: [CLLocationCoordinate2D], colorHex: String?) {
    self.coordinates = coordinates
    self.colorHex = colorHex
  }
}
