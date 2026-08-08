//
//  AnchorEvitementPoint.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Represents a single vessel location sample recorded during an anchor watch session.
/// Wraps `CodableCoordinate` for strict thread safety and JSON serialization compatibility.
public struct AnchorEvitementPoint: Codable, Sendable, Equatable {
  private let storedCoordinate: CodableCoordinate
  public let timestamp: Date

  /// Public coordinate accessor for map rendering and spatial calculations.
  public var coordinate: CLLocationCoordinate2D {
    storedCoordinate.coordinate
  }

  public init(coordinate: CLLocationCoordinate2D, timestamp: Date = Date()) {
    self.storedCoordinate = CodableCoordinate(coordinate)
    self.timestamp = timestamp
  }

  public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees, timestamp: Date = Date()) {
    self.storedCoordinate = CodableCoordinate(latitude: latitude, longitude: longitude)
    self.timestamp = timestamp
  }
}
