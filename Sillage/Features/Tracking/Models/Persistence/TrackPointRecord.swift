//
//  TrackPointRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-13.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence Model for Track Point
/// The raw database persistence entity for a recorded track point.
/// When fetched from the database, it must be mapped to the `TrackPoint` domain model for in-memory physical type safety.
public struct TrackPointRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public var id: Int64?
  public var sessionId: String
  public var timestamp_unix: Double
  public var segmentIndex: Int
  public var latitude_deg: Double
  public var longitude_deg: Double
  public var horizontalAccuracy_m: Double
  public var speedOverGround_mps: Double?
  public var courseOverGround_deg: Double?

  public static let databaseTableName = "track_point"

  // Association with TrackSessionRecord
  public static let trackSession = belongsTo(TrackSessionRecord.self)
  public var trackSession: QueryInterfaceRequest<TrackSessionRecord> {
    request(for: TrackPointRecord.trackSession)
  }

  public init(
    id: Int64?,
    sessionId: String,
    timestamp: Date,
    segmentIndex: Int,
    latitude: Measurement<UnitAngle>,
    longitude: Measurement<UnitAngle>,
    horizontalAccuracy: Measurement<UnitLength>,
    speedOverGround: Measurement<UnitSpeed>? = nil,
    courseOverGround: Measurement<UnitAngle>? = nil,
  ) {
    self.id = id
    self.sessionId = sessionId
    self.timestamp_unix = timestamp.timeIntervalSince1970
    self.segmentIndex = segmentIndex
    self.latitude_deg = latitude.converted(to: .degrees).value
    self.longitude_deg = longitude.converted(to: .degrees).value
    self.horizontalAccuracy_m = horizontalAccuracy.converted(to: .meters).value
    self.speedOverGround_mps = speedOverGround.map { $0.converted(to: .metersPerSecond).value }
    self.courseOverGround_deg = courseOverGround.map { $0.converted(to: .degrees).value }
  }
}

// MARK: - Domain Mapping

extension TrackPointRecord {
  /// Converts the domain `TrackPoint` into a persistence `TrackPointRecord`.
  public init(domainModel: TrackPoint, sessionId: String) {
    self.init(
      id: nil,
      sessionId: sessionId,
      timestamp: domainModel.timestamp,
      segmentIndex: domainModel.segmentIndex,
      latitude: domainModel.latitude,
      longitude: domainModel.longitude,
      horizontalAccuracy: domainModel.horizontalAccuracy,
      speedOverGround: domainModel.speedOverGround,
      courseOverGround: domainModel.courseOverGround,
    )
  }
  
  public enum Columns: String, ColumnExpression {
    case id
    case sessionId
    case timestamp_unix
    case segmentIndex
    case latitude_deg
    case longitude_deg
    case horizontalAccuracy_m
    case speedOverGround_mps
    case courseOverGround_deg
  }
  
  /// Converts the persistence `TrackPointRecord` into a domain `TrackPoint`.
  public var domainModel: TrackPoint {
    let speedOverGround: Measurement<UnitSpeed>? = speedOverGround_mps.map { Measurement(value: $0, unit: .metersPerSecond) }
    let courseOverGround: Measurement<UnitAngle>? = courseOverGround_deg.map { Measurement(value: $0, unit: .degrees) }
    
    return TrackPoint(
      timestamp: Date(timeIntervalSince1970: timestamp_unix),
      segmentIndex: segmentIndex,
      latitude: Measurement(value: latitude_deg, unit: .degrees),
      longitude: Measurement(value: longitude_deg, unit: .degrees),
      horizontalAccuracy: Measurement(value: horizontalAccuracy_m, unit: .meters),
      speedOverGround: speedOverGround,
      courseOverGround: courseOverGround,
    )
  }
}
