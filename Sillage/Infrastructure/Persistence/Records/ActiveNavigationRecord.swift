//
//  ActiveNavigationRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import GRDB

/// GRDB singleton persistence record for the currently active GoTo navigation leg.
/// Enforces `id = 1` and a foreign key (`ON DELETE CASCADE`) onto `waypoint(id)`.
public struct ActiveNavigationRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
  public static let databaseTableName = "active_navigation"
  nonisolated public static let singletonID = 1

  public var id: Int
  public var waypoint_id: String
  public var origin_latitude_deg: CLLocationDegrees?
  public var origin_longitude_deg: CLLocationDegrees?
  public var activated_at_unix: Double

  nonisolated public init(
    id: Int = Self.singletonID,
    waypoint_id: String,
    originCoordinate: CLLocationCoordinate2D?,
    activatedAt: Date
  ) {
    self.id = id
    self.waypoint_id = waypoint_id
    self.origin_latitude_deg = originCoordinate?.latitude
    self.origin_longitude_deg = originCoordinate?.longitude
    self.activated_at_unix = activatedAt.timeIntervalSince1970
  }

  public enum Columns: String, ColumnExpression {
    case id
    case waypoint_id
    case origin_latitude_deg
    case origin_longitude_deg
    case activated_at_unix
  }
}

// MARK: - Domain Mapping

extension ActiveNavigationRecord {
  nonisolated public var originCoordinate: CLLocationCoordinate2D? {
    guard let lat = origin_latitude_deg, let lon = origin_longitude_deg else {
      return nil
    }
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }

  nonisolated public func toDomain(waypoint: Waypoint) -> ActiveNavigationLeg {
    ActiveNavigationLeg(
      waypoint: waypoint,
      originCoordinate: originCoordinate,
      activatedAt: Date(timeIntervalSince1970: activated_at_unix)
    )
  }
}
