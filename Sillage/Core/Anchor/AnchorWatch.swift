//
//  AnchorWatch.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Pure domain data model representing an anchor watch session.
/// Stores the anchor location, radius, creation date, and initial GPS accuracy.
public struct AnchorWatch: Codable, Sendable, Equatable {
  // Serializable internal storage (optional for pending drops before GPS lock)
  private let storedCoordinate: CodableCoordinate?
  public let radius: Measurement<UnitLength>
  public let createdAt: Date
  
  /// The initial GPS horizontal accuracy when the anchor drop was performed.
  /// Persisted as a `Measurement<UnitLength>` to allow UI warning badges without losing precision telemetry.
  public let initialAccuracy: Measurement<UnitLength>?
  
  // Public accessor for the domain
  public var coordinate: CLLocationCoordinate2D? {
    storedCoordinate?.coordinate
  }
  
  public init(
    coordinate: CLLocationCoordinate2D? = nil,
    radius: Measurement<UnitLength>,
    initialAccuracy: Measurement<UnitLength>? = nil,
    createdAt: Date = Date()
  ) {
    if let coord = coordinate {
      self.storedCoordinate = CodableCoordinate(coord)
    } else {
      self.storedCoordinate = nil
    }
    self.radius = radius
    self.initialAccuracy = initialAccuracy
    self.createdAt = createdAt
  }
  
  private enum CodingKeys: String, CodingKey {
    case storedCoordinate = "coordinate"
    case radius
    case createdAt
    case initialAccuracy
  }
}
