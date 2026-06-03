//
//  WaypointRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence Model for a Waypoint
public struct WaypointRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public var id: String
  public var name: String
  public var description: String?
  public var symbol: String?
  public var color_hex: String?
  public var isVisible: Bool
  public var latitude_deg: Double
  public var longitude_deg: Double
  public var timestamp_unix: Double
  
  public static let databaseTableName = "waypoint"

  public init(id: String, name: String, description: String? = nil, symbol: String? = nil, color_hex: String? = nil, isVisible: Bool = true, latitude_deg: Double, longitude_deg: Double, timestamp: Date) {
    self.id = id
    self.name = name
    self.description = description
    self.symbol = symbol
    self.color_hex = color_hex
    self.isVisible = isVisible
    self.latitude_deg = latitude_deg
    self.longitude_deg = longitude_deg
    self.timestamp_unix = timestamp.timeIntervalSince1970
  }
  
  public enum Columns: String, ColumnExpression {
    case id
    case name
    case description
    case symbol
    case color_hex
    case isVisible
    case latitude_deg
    case longitude_deg
    case timestamp_unix
  }
}

// MARK: - Domain Mapping

extension WaypointRecord {
  /// Converts the persistence `WaypointRecord` into a domain `Waypoint`.
  public func toDomain() -> Waypoint {
    return Waypoint(
      id: id,
      name: name,
      description: description,
      symbol: symbol,
      colorHex: color_hex,
      isVisible: isVisible,
      latitude: Measurement(value: latitude_deg, unit: UnitAngle.degrees),
      longitude: Measurement(value: longitude_deg, unit: UnitAngle.degrees),
      timestamp: Date(timeIntervalSince1970: timestamp_unix)
    )
  }

  /// Converts the domain `Waypoint` into a persistence `WaypointRecord`.
  public init(domainModel: Waypoint) {
    self.id = domainModel.id
    self.name = domainModel.name
    self.description = domainModel.description
    self.symbol = domainModel.symbol
    self.color_hex = domainModel.colorHex
    self.isVisible = domainModel.isVisible
    self.latitude_deg = domainModel.latitude.converted(to: .degrees).value
    self.longitude_deg = domainModel.longitude.converted(to: .degrees).value
    self.timestamp_unix = domainModel.timestamp.timeIntervalSince1970
  }
}
