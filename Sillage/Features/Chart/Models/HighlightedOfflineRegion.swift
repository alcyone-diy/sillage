//
//  HighlightedOfflineRegion.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreLocation
import Foundation

/// Represents an offline chart package currently highlighted on the map for user inspection.
public struct HighlightedOfflineRegion: Sendable, Equatable {
  public let id: String
  public let name: String
  public let bounds: GeographicBoundingBox

  public init(id: String, name: String, bounds: GeographicBoundingBox) {
    self.id = id
    self.name = name
    self.bounds = bounds
  }

  /// Geographic center coordinate of the region's bounding box.
  public var center: CLLocationCoordinate2D {
    bounds.center
  }

  /// Closed polygon coordinates defining the region's bounding boundary.
  public var polygonCoordinates: [CLLocationCoordinate2D] {
    bounds.polygonCoordinates
  }
}
