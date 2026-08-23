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
import CoreLocation

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
  public var southLatitude_deg: CLLocationDegrees?
  public var northLatitude_deg: CLLocationDegrees?
  public var westLongitude_deg: CLLocationDegrees?
  public var eastLongitude_deg: CLLocationDegrees?
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
    let boundingBox: GeographicBoundingBox?
    if let southLat = southLatitude_deg, let northLat = northLatitude_deg, let westLon = westLongitude_deg, let eastLon = eastLongitude_deg {
      boundingBox = GeographicBoundingBox(
        southWest: CLLocationCoordinate2D(latitude: southLat, longitude: westLon),
        northEast: CLLocationCoordinate2D(latitude: northLat, longitude: eastLon)
      )
    } else {
      boundingBox = nil
    }

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
      boundingBox: boundingBox,
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
    self.southLatitude_deg = domainModel.boundingBox?.southWest.latitude
    self.northLatitude_deg = domainModel.boundingBox?.northEast.latitude
    self.westLongitude_deg = domainModel.boundingBox?.southWest.longitude
    self.eastLongitude_deg = domainModel.boundingBox?.northEast.longitude
    self.maxSpeedOverGround_mps = domainModel.maxSpeedOverGround?.converted(to: .metersPerSecond).value
    self.segmentCount = domainModel.segmentCount
    self.totalPointCount = domainModel.totalPointCount
    self.color_hex = domainModel.colorHex
  }
}
