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
nonisolated public struct AnchorWatch: Codable, Sendable, Equatable {
  // Serializable internal storage (optional for pending drops before GPS lock)
  private let storedCoordinate: CodableCoordinate?
  public let radius: Measurement<UnitLength>
  public let createdAt: Date

  /// The initial GPS horizontal accuracy when the anchor drop was performed.
  /// Persisted as a `Measurement<UnitLength>` to allow UI warning badges without losing precision telemetry.
  public let initialAccuracy: Measurement<UnitLength>?

  /// Historical vessel swing samples recorded during this anchor watch session.
  /// Used to render the anchorage swing trail on the chart.
  public private(set) var swingHistory: [AnchorSwingPoint]

  // Public accessor for the domain
  public var coordinate: CLLocationCoordinate2D? {
    storedCoordinate?.coordinate
  }

  public init(
    coordinate: CLLocationCoordinate2D? = nil,
    radius: Measurement<UnitLength>,
    initialAccuracy: Measurement<UnitLength>? = nil,
    createdAt: Date = Date(),
    swingHistory: [AnchorSwingPoint] = []
  ) {
    if let coord = coordinate {
      self.storedCoordinate = CodableCoordinate(coord)
    } else {
      self.storedCoordinate = nil
    }
    self.radius = radius
    self.initialAccuracy = initialAccuracy
    self.createdAt = createdAt
    self.swingHistory = swingHistory
  }

  /// Appends a new swing sample while purging points older than `maxAge` (default 24 hours)
  /// and bounding maximum array capacity to `maxPoints` (default 1000) to ensure memory safety.
  /// Technical Design Choice: Purely spatial sampling ensures that stationary vessels do not
  /// flood the circular buffer over long anchorage periods.
  public mutating func appendSwingPoint(
    _ point: AnchorSwingPoint,
    maxAge: TimeInterval = 24 * 3600,
    maxPoints: Int = 1000
  ) {
    let cutoff = point.timestamp.addingTimeInterval(-maxAge)
    var updated = swingHistory.filter { $0.timestamp >= cutoff }
    updated.append(point)
    if updated.count > maxPoints {
      updated.removeFirst(updated.count - maxPoints)
    }
    self.swingHistory = updated
  }

  private enum CodingKeys: String, CodingKey {
    case storedCoordinate = "coordinate"
    case radius
    case createdAt
    case initialAccuracy
    case swingHistory
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case evitementHistory
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.storedCoordinate = try container.decodeIfPresent(CodableCoordinate.self, forKey: .storedCoordinate)
    self.radius = try container.decode(Measurement<UnitLength>.self, forKey: .radius)
    self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    self.initialAccuracy = try container.decodeIfPresent(Measurement<UnitLength>.self, forKey: .initialAccuracy)
    // Preserve seamless decoding of persisted sessions saved prior to the `evitementHistory` -> `swingHistory` rename.
    if let history = try container.decodeIfPresent([AnchorSwingPoint].self, forKey: .swingHistory) {
      self.swingHistory = history
    } else {
      let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
      self.swingHistory = try legacyContainer.decodeIfPresent([AnchorSwingPoint].self, forKey: .evitementHistory) ?? []
    }
  }
}
