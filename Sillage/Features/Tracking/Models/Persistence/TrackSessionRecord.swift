//
//  TrackSessionRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-13.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence Model for Track Session
public struct TrackSessionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public var id: String
  public var startTime: Date
  public var endTime: Date?
  public var name: String?
  public var durationSeconds: Double?
  public var totalDistanceMetres: Double?

  public static let databaseTableName = "track_session"

  public init(id: String, startTime: Date, endTime: Date? = nil, name: String? = nil, durationSeconds: Double? = nil, totalDistanceMetres: Double? = nil) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.name = name
    self.durationSeconds = durationSeconds
    self.totalDistanceMetres = totalDistanceMetres
  }

  public var totalDistance: Measurement<UnitLength>? {
    guard let meters = totalDistanceMetres else { return nil }
    return Measurement(value: meters, unit: .meters)
  }

  public enum Columns: String, ColumnExpression {
    case id
    case startTime
    case endTime
    case name
    case durationSeconds
    case totalDistanceMetres
  }

  // Association with TrackPointRecord
  public static let trackPoints = hasMany(TrackPointRecord.self)
  public var trackPoints: QueryInterfaceRequest<TrackPointRecord> {
    request(for: TrackSessionRecord.trackPoints)
  }
}

// MARK: - Domain Mapping

extension TrackSessionRecord {
  /// Converts the persistence `TrackSessionRecord` into a domain `TrackSession`.
  public func toDomain() -> TrackSession {
    let duration: Duration? = durationSeconds.map { .seconds($0) }
    return TrackSession(
      id: id,
      startTime: startTime,
      endTime: endTime,
      name: name,
      duration: duration,
      totalDistance: totalDistance
    )
  }

  /// Converts the domain `TrackSession` into a persistence `TrackSessionRecord`.
  public init(domainModel: TrackSession) {
    let durationSecs: Double? = domainModel.duration.map { duration in
      Double(duration.components.seconds) + (Double(duration.components.attoseconds) / 1e18)
    }
    self.init(
      id: domainModel.id,
      startTime: domainModel.startTime,
      endTime: domainModel.endTime,
      name: domainModel.name,
      durationSeconds: durationSecs,
      totalDistanceMetres: domainModel.totalDistance?.converted(to: .meters).value
    )
  }
}
