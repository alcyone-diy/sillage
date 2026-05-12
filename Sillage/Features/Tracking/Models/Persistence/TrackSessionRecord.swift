//
//  TrackSessionRecord.swift
//  Alcyone Sillage
//

import Foundation
import GRDB

/// GRDB Persistence Model for Track Session
public struct TrackSessionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public var id: String
  public var startTime: Date
  public var endTime: Date?
  public var name: String?

  public static let databaseTableName = "track_session"

  public init(id: String, startTime: Date, endTime: Date? = nil, name: String? = nil) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.name = name
  }

  // Association with TrackPointRecord
  public static let trackPoints = hasMany(TrackPointRecord.self)
  public var trackPoints: QueryInterfaceRequest<TrackPointRecord> {
    request(for: TrackSessionRecord.trackPoints)
  }
}
