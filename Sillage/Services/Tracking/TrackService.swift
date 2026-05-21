//
//  TrackService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-18.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB
import OSLog

/// A thread-safe service providing read and write operations for track sessions in the database.
public struct TrackService: Sendable {
  private let databaseManager: DatabaseManager

  public init(databaseManager: DatabaseManager) {
    self.databaseManager = databaseManager
  }

  /// Observes saved track sessions, ordered by start time descending, in real-time.
  /// - Returns: An AsyncSequence emitting arrays of `TrackSessionRecord` whenever the database updates.
  public func observeTrackSessions() -> some AsyncSequence<[TrackSession], Error> {
    let observation = ValueObservation.tracking { db in
      let records = try TrackSessionRecord
        .order(TrackSessionRecord.Columns.startTime_unix.desc)
        .fetchAll(db)
      
      // The mapping is performed on the database queue,
      // protecting the MainActor from heavy computation if the list is long.
      return records.map { $0.toDomain() }
    }
    
    return observation.values(in: databaseManager.reader)
  }

  /// Deletes a track session and its associated points (via cascade constraint) by id.
  /// - Parameter id: The unique identifier of the track session to delete.
  public func deleteSession(id: String) async throws {
    _ = try await databaseManager.write { db in
      let deleted = try TrackSessionRecord.deleteOne(db, key: id)
      if deleted {
        Logger.database.info("Successfully deleted track session: \(id, privacy: .public)")
      } else {
        Logger.database.warning("Track session not found for deletion: \(id, privacy: .public)")
      }
    }
  }

  /// Observes a single track session by its ID, reacting to database updates.
  /// - Parameter id: The ID of the session to observe.
  /// - Returns: An AsyncSequence emitting `TrackSession?` whenever the session changes in the database.
  public func observeTrackSession(id: String) -> some AsyncSequence<TrackSession?, Error> {
    let observation = ValueObservation.tracking { db in
      try TrackSessionRecord.fetchOne(db, key: id)?.toDomain()
    }
    return observation.values(in: databaseManager.reader)
  }

  /// Summary statistics for a track session's recorded points.
  public struct TrackStats: Sendable {
    public let pointsCount: Int
    public let segmentCount: Int
    public let maxSpeed: Measurement<UnitSpeed>?
    
    nonisolated public init(
      pointsCount: Int,
      segmentCount: Int,
      maxSpeed: Measurement<UnitSpeed>?
    ) {
      self.pointsCount = pointsCount
      self.segmentCount = segmentCount
      self.maxSpeed = maxSpeed
    }
  }

  /// Fetches summary statistics for a track session's recorded points.
  /// - Parameter id: The unique identifier of the track session.
  /// - Returns: A `TrackStats` containing aggregate metrics of the track.
  public func fetchTrackStats(id: String) async throws -> TrackStats {
    try await databaseManager.dbPool.read { db in
      let pointsCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM track_point WHERE sessionId = ?",
        arguments: [id]
      ) ?? 0
      
      let segmentCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(DISTINCT segmentIndex) FROM track_point WHERE sessionId = ?",
        arguments: [id]
      ) ?? 0
      
      let maxSpeedMps = try Double.fetchOne(
        db,
        sql: "SELECT MAX(sog_mps) FROM track_point WHERE sessionId = ?",
        arguments: [id]
      )
      
      let maxSpeed = maxSpeedMps.map { Measurement(value: $0, unit: UnitSpeed.metersPerSecond) }
      
      return TrackStats(
        pointsCount: pointsCount,
        segmentCount: segmentCount,
        maxSpeed: maxSpeed
      )
    }
  }

  /// Updates the name and description of a track session.
  /// - Parameters:
  ///   - id: The unique identifier of the track session.
  ///   - name: The new name (or nil).
  ///   - description: The new description (or nil).
  public func updateSession(id: String, name: String?, description: String?) async throws {
    _ = try await databaseManager.write { db in
      if var record = try TrackSessionRecord.fetchOne(db, key: id) {
        record.name = name
        record.description = description
        try record.update(db)
        Logger.database.info("Successfully updated track session: \(id, privacy: .public)")
      } else {
        Logger.database.warning("Track session not found for update: \(id, privacy: .public)")
      }
    }
  }
}
