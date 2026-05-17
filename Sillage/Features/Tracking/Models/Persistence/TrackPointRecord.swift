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
public struct TrackPointRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public var id: Int64?
  public var sessionId: String
  public var timestamp: Date
  public var segmentIndex: Int
  public var latitude_deg: Double
  public var longitude_deg: Double
  public var horizontalAccuracy_m: Double
  public var sog_mps: Double?
  public var cog_deg: Double?

  public static let databaseTableName = "track_point"

  // Association with TrackSessionRecord
  public static let trackSession = belongsTo(TrackSessionRecord.self)
  public var trackSession: QueryInterfaceRequest<TrackSessionRecord> {
    request(for: TrackPointRecord.trackSession)
  }

  public init(id: Int64? = nil, sessionId: String, timestamp: Date, segmentIndex: Int, latitude_deg: Double, longitude_deg: Double, horizontalAccuracy_m: Double, sog_mps: Double? = nil, cog_deg: Double? = nil) {
    self.id = id
    self.sessionId = sessionId
    self.timestamp = timestamp
    self.segmentIndex = segmentIndex
    self.latitude_deg = latitude_deg
    self.longitude_deg = longitude_deg
    self.horizontalAccuracy_m = horizontalAccuracy_m
    self.sog_mps = sog_mps
    self.cog_deg = cog_deg
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
      latitude_deg: domainModel.latitude,
      longitude_deg: domainModel.longitude,
      horizontalAccuracy_m: domainModel.horizontalAccuracy.converted(to: .meters).value,
      sog_mps: domainModel.sog?.converted(to: .metersPerSecond).value,
      cog_deg: domainModel.cog?.converted(to: .degrees).value,
    )
  }

  /// Converts the persistence `TrackPointRecord` into a domain `TrackPoint`.
  public var domainModel: TrackPoint {
    let sog: Measurement<UnitSpeed>? = sog_mps.map { Measurement(value: $0, unit: .metersPerSecond) }
    let cog: Measurement<UnitAngle>? = cog_deg.map { Measurement(value: $0, unit: .degrees) }
    let horizontalAccuracy: Measurement<UnitLength> = Measurement(value: horizontalAccuracy_m, unit: .meters)
    
    return TrackPoint(
      timestamp: timestamp,
      segmentIndex: segmentIndex,
      latitude: latitude_deg,
      longitude: longitude_deg,
      horizontalAccuracy: horizontalAccuracy,
      sog: sog,
      cog: cog,
    )
  }
}
