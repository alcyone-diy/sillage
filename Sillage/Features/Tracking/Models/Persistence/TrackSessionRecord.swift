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
  public var startTimestamp_unix: Double
  public var endTimestamp_unix: Double?
  public var name: String?
  public var description: String?
  public var startLocation: String?
  public var endLocation: String?
  public var totalDuration_s: Double?
  public var totalDistanceOverGround_m: Double?
  public var southLatitude_deg: Double?
  public var northLatitude_deg: Double?
  public var westLongitude_deg: Double?
  public var eastLongitude_deg: Double?
  public var maxSpeedOverGround_mps: Double?
  public var segmentCount: Int = 0
  public var totalPointCount: Int = 0
  public var color_hex: String?

  public static let databaseTableName = "track_session"

  public init(id: String, startTime: Date) {
    self.id = id
    self.startTimestamp_unix = startTime.timeIntervalSince1970
  }

  public enum Columns: String, ColumnExpression {
    case id
    case startTimestamp_unix
    case endTimestamp_unix
    case name
    case description
    case startLocation
    case endLocation
    case totalDuration_s
    case totalDistanceOverGround_m
    case southLatitude_deg
    case northLatitude_deg
    case westLongitude_deg
    case eastLongitude_deg
    case maxSpeedOverGround_mps
    case segmentCount
    case totalPointCount
    case color_hex
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
      startTime: Date(timeIntervalSince1970: startTimestamp_unix),
      endTime: endTimestamp_unix.map { Date(timeIntervalSince1970: $0) },
      name: name,
      description: description,
      startLocation: startLocation,
      endLocation: endLocation,
      totalDuration: totalDuration_s.map { .seconds($0) },
      totalDistanceOverGround: totalDistanceOverGround_m.map { Measurement(value: $0, unit: UnitLength.meters) },
      southLatitude: southLatitude_deg.map { Measurement(value: $0, unit: .degrees) },
      northLatitude: northLatitude_deg.map { Measurement(value: $0, unit: .degrees) },
      westLongitude: westLongitude_deg.map { Measurement(value: $0, unit: .degrees) },
      eastLongitude: eastLongitude_deg.map { Measurement(value: $0, unit: .degrees) },
      maxSpeedOverGround: maxSpeedOverGround_mps.flatMap { $0 >= 0 ? Measurement(value: $0, unit: .metersPerSecond) : nil },
      segmentCount: segmentCount,
      totalPointCount: totalPointCount,
      colorHex: color_hex
    )
  }

  /// Converts the domain `TrackSession` into a persistence `TrackSessionRecord`.
  public init(domainModel: TrackSession) {
    self.id = domainModel.id
    self.startTimestamp_unix = domainModel.startTime.timeIntervalSince1970
    self.endTimestamp_unix = domainModel.endTime?.timeIntervalSince1970
    self.name = domainModel.name
    self.description = domainModel.description
    self.startLocation = domainModel.startLocation
    self.endLocation = domainModel.endLocation
    self.totalDuration_s = domainModel.totalDuration?.timeInterval
    self.totalDistanceOverGround_m = domainModel.totalDistanceOverGround?.converted(to: .meters).value
    self.southLatitude_deg = domainModel.southLatitude?.converted(to: .degrees).value
    self.northLatitude_deg = domainModel.northLatitude?.converted(to: .degrees).value
    self.westLongitude_deg = domainModel.westLongitude?.converted(to: .degrees).value
    self.eastLongitude_deg = domainModel.eastLongitude?.converted(to: .degrees).value
    self.maxSpeedOverGround_mps = domainModel.maxSpeedOverGround?.converted(to: .metersPerSecond).value
    self.segmentCount = domainModel.segmentCount
    self.totalPointCount = domainModel.totalPointCount
    self.color_hex = domainModel.colorHex
  }
}
