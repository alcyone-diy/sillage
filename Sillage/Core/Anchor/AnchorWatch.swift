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
  
  /// Historical vessel swing samples recorded during this anchor watch session.
  /// Used to render the anchorage swing trace (evitement line) on the chart.
  public private(set) var evitementHistory: [AnchorEvitementPoint]
  
  // Public accessor for the domain
  public var coordinate: CLLocationCoordinate2D? {
    storedCoordinate?.coordinate
  }
  
  public init(
    coordinate: CLLocationCoordinate2D? = nil,
    radius: Measurement<UnitLength>,
    initialAccuracy: Measurement<UnitLength>? = nil,
    createdAt: Date = Date(),
    evitementHistory: [AnchorEvitementPoint] = []
  ) {
    if let coord = coordinate {
      self.storedCoordinate = CodableCoordinate(coord)
    } else {
      self.storedCoordinate = nil
    }
    self.radius = radius
    self.initialAccuracy = initialAccuracy
    self.createdAt = createdAt
    self.evitementHistory = evitementHistory
  }

  /// Appends a new evitement sample while purging points older than `maxAge` (default 24 hours)
  /// and bounding maximum array capacity to `maxPoints` (default 1000) to ensure memory safety.
  /// Technical Design Choice: Purely spatial sampling ensures that stationary vessels do not
  /// flood the circular buffer over long anchorage periods.
  public mutating func appendEvitementPoint(
    _ point: AnchorEvitementPoint,
    maxAge: TimeInterval = 24 * 3600,
    maxPoints: Int = 1000
  ) {
    let cutoff = point.timestamp.addingTimeInterval(-maxAge)
    var updated = evitementHistory.filter { $0.timestamp >= cutoff }
    updated.append(point)
    if updated.count > maxPoints {
      updated.removeFirst(updated.count - maxPoints)
    }
    self.evitementHistory = updated
  }
  
  private enum CodingKeys: String, CodingKey {
    case storedCoordinate = "coordinate"
    case radius
    case createdAt
    case initialAccuracy
    case evitementHistory
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.storedCoordinate = try container.decodeIfPresent(CodableCoordinate.self, forKey: .storedCoordinate)
    self.radius = try container.decode(Measurement<UnitLength>.self, forKey: .radius)
    self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    self.initialAccuracy = try container.decodeIfPresent(Measurement<UnitLength>.self, forKey: .initialAccuracy)
    self.evitementHistory = try container.decodeIfPresent([AnchorEvitementPoint].self, forKey: .evitementHistory) ?? []
  }
}

