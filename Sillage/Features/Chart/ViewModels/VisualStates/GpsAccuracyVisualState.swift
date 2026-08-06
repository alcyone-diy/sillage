//
//  GpsAccuracyVisualState.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Represents the visual polygon coordinates for the GPS accuracy circle.
public struct GpsAccuracyVisualState: Equatable, Sendable {
  public let coordinates: [CLLocationCoordinate2D]
  
  public init(coordinates: [CLLocationCoordinate2D]) {
    self.coordinates = coordinates
  }
}
