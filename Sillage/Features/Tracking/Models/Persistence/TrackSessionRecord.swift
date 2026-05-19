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
  public var startTime_unix: Double
  public var endTime_unix: Double?
  public var name: String?
  public var duration_s: Double?
  public var totalDistance_m: Double?
  public var minLatitude_deg: Double?
  public var maxLatitude_deg: Double?
  public var minLongitude_deg: Double?
  public var maxLongitude_deg: Double?

  public static let databaseTableName = "track_session"

  public init(id: String, startTime: Date) {
    self.id = id
    self.startTime_unix = startTime.timeIntervalSince1970
  }

  public enum Columns: String, ColumnExpression {
    case id
    case startTime_unix
    case endTime_unix
    case name
    case duration_s
    case totalDistance_m
    case minLatitude_deg
    case maxLatitude_deg
    case minLongitude_deg
    case maxLongitude_deg
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
    return TrackSession(
      id: id,
      startTime: Date(timeIntervalSince1970: startTime_unix),
      endTime: endTime_unix.map { Date(timeIntervalSince1970: $0) },
      name: name,
      duration: duration_s.map { .seconds($0) },
      totalDistance: totalDistance_m.map { Measurement(value: $0, unit: UnitLength.meters) },
      minLatitude: minLatitude_deg.map { Measurement(value: $0, unit: .degrees) },
      maxLatitude: maxLatitude_deg.map { Measurement(value: $0, unit: .degrees) },
      minLongitude: minLongitude_deg.map { Measurement(value: $0, unit: .degrees) },
      maxLongitude: maxLongitude_deg.map { Measurement(value: $0, unit: .degrees) }
    )
  }

  /// Converts the domain `TrackSession` into a persistence `TrackSessionRecord`.
  public init(domainModel: TrackSession) {
    let durationSecs: Double? = domainModel.duration.map { duration in
      Double(duration.components.seconds) + (Double(duration.components.attoseconds) / 1e18)
    }
    self.id = domainModel.id
    self.startTime_unix = domainModel.startTime.timeIntervalSince1970
    self.endTime_unix = domainModel.endTime?.timeIntervalSince1970
    self.name = domainModel.name
    self.duration_s = durationSecs
    self.totalDistance_m = domainModel.totalDistance?.converted(to: .meters).value
    self.minLatitude_deg = domainModel.minLatitude?.converted(to: .degrees).value
    self.maxLatitude_deg = domainModel.maxLatitude?.converted(to: .degrees).value
    self.minLongitude_deg = domainModel.minLongitude?.converted(to: .degrees).value
    self.maxLongitude_deg = domainModel.maxLongitude?.converted(to: .degrees).value
  }
}
