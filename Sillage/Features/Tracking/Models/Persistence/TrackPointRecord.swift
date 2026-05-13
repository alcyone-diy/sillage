//
//  TrackPointRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-13.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

//
//  TrackPointRecord.swift
//  Alcyone Sillage
//

import Foundation
import GRDB

/// GRDB Persistence Model for Track Point
public struct TrackPointRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public var id: Int64?
  public var sessionId: String
  public var latitude_deg: Double
  public var longitude_deg: Double
  public var timestamp: Date
  public var sog_mps: Double?
  public var cog_deg: Double?
  public var accuracy_m: Double?

  public static let databaseTableName = "track_point"

  // Association with TrackSessionRecord
  public static let trackSession = belongsTo(TrackSessionRecord.self)
  public var trackSession: QueryInterfaceRequest<TrackSessionRecord> {
    request(for: TrackPointRecord.trackSession)
  }

  public init(id: Int64? = nil, sessionId: String, latitude_deg: Double, longitude_deg: Double, timestamp: Date, sog_mps: Double? = nil, cog_deg: Double? = nil, accuracy_m: Double? = nil) {
    self.id = id
    self.sessionId = sessionId
    self.latitude_deg = latitude_deg
    self.longitude_deg = longitude_deg
    self.timestamp = timestamp
    self.sog_mps = sog_mps
    self.cog_deg = cog_deg
    self.accuracy_m = accuracy_m
  }
}

// MARK: - Domain Mapping

extension TrackPointRecord {
  /// Converts the domain `TrackPoint` into a persistence `TrackPointRecord`.
  public init(domainModel: TrackPoint, sessionId: String) {
    self.init(
      id: nil,
      sessionId: sessionId,
      latitude_deg: domainModel.latitude,
      longitude_deg: domainModel.longitude,
      timestamp: domainModel.timestamp,
      sog_mps: domainModel.sog?.converted(to: .metersPerSecond).value,
      cog_deg: domainModel.cog?.converted(to: .degrees).value,
      accuracy_m: domainModel.accuracy?.converted(to: .meters).value
    )
  }

  /// Converts the persistence `TrackPointRecord` into a domain `TrackPoint`.
  public var domainModel: TrackPoint {
    let sog: Measurement<UnitSpeed>? = sog_mps.map { Measurement(value: $0, unit: .metersPerSecond) }
    let cog: Measurement<UnitAngle>? = cog_deg.map { Measurement(value: $0, unit: .degrees) }
    let accuracy: Measurement<UnitLength>? = accuracy_m.map { Measurement(value: $0, unit: .meters) }
    
    return TrackPoint(
      latitude: latitude_deg,
      longitude: longitude_deg,
      timestamp: timestamp,
      sog: sog,
      cog: cog,
      accuracy: accuracy
    )
  }
}
