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
  public func observeTrackSessions() -> AsyncValueObservation<[TrackSession]> {
    let observation = ValueObservation.tracking { db in
      let records = try TrackSessionRecord
        .order(TrackSessionRecord.Columns.startTimestamp_unix.desc)
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
  public func observeTrackSession(id: String) -> AsyncValueObservation<TrackSession?> {
    let observation = ValueObservation.tracking { db in
      try TrackSessionRecord.fetchOne(db, key: id)?.toDomain()
    }
    return observation.values(in: databaseManager.reader)
  }
  
  /// Updates the name and description of a track session.
  /// - Parameters:
  ///   - id: The unique identifier of the track session.
  ///   - name: The new name (or nil).
  ///   - description: The new description (or nil).
  public func updateSession(
    id: String,
    name: String?,
    description: String?
  ) async throws {
    _ = try await databaseManager.write { db in
      let updatedCount = try TrackSessionRecord
        .filter(TrackSessionRecord.Columns.id == id)
        .updateAll(
          db,
          TrackSessionRecord.Columns.name.set(to: name),
          TrackSessionRecord.Columns.description.set(to: description)
        )
      if updatedCount > 0 {
        Logger.database.info("Successfully updated metadata for track session: \(id, privacy: .public)")
      } else {
        Logger.database.warning("Track session not found for metadata update: \(id, privacy: .public)")
      }
    }
  }
  
  /// Fetches all track points for a given session.
  /// - Parameter sessionID: The unique identifier of the track session.
  /// - Returns: An array of `TrackPoint`.
  public func fetchTrackPoints(for sessionID: String) async throws -> [TrackPoint] {
    try await databaseManager.reader.read { db in
      let records = try TrackPointRecord
        .filter(TrackPointRecord.Columns.sessionID == sessionID)
        .order(TrackPointRecord.Columns.timestamp_unix.asc)
        .fetchAll(db)
      return records.map { $0.domainModel }
    }
  }
  
  /// Exports a track session to a GPX file, providing an `AsyncThrowingStream<Double, Error>` for real-time progress.
  /// - Parameters:
  ///   - id: The unique identifier of the track session.
  ///   - url: The destination file URL.
  /// - Returns: An `AsyncThrowingStream<Double, Error>` emitting normalized progress (0.0 to 1.0).
  public func exportSession(id: String, to url: URL) -> AsyncThrowingStream<Double, Error> {
    AsyncThrowingStream { continuation in
      let task = Task.detached(priority: .userInitiated) {
        do {
          _ = try await self.databaseManager.reader.read { db in
            let sessionName = try TrackSessionRecord.fetchOne(db, key: id)?.name
            let totalCount = try TrackPointRecord
              .filter(TrackPointRecord.Columns.sessionID == id)
              .fetchCount(db)
            let request = TrackPointRecord
              .filter(TrackPointRecord.Columns.sessionID == id)
              .order(TrackPointRecord.Columns.timestamp_unix.asc)
            let cursor = try request.fetchCursor(db)

            return try GPXExportService.export(
              sessionID: id,
              sessionName: sessionName,
              cursor: cursor,
              totalCount: totalCount,
              to: url,
              onProgress: { progress in
                continuation.yield(progress)
              }
            )
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  /// Exports a track session directly to a GPX file without observing intermediate progress.
  /// - Parameters:
  ///   - id: The unique identifier of the track session.
  ///   - url: The destination file URL.
  /// - Returns: The number of exported track points.
  @discardableResult
  public func exportSessionDirect(id: String, to url: URL) async throws -> Int {
    try await databaseManager.reader.read { db in
      let sessionName = try TrackSessionRecord.fetchOne(db, key: id)?.name
      let totalCount = try TrackPointRecord
        .filter(TrackPointRecord.Columns.sessionID == id)
        .fetchCount(db)
      let request = TrackPointRecord
        .filter(TrackPointRecord.Columns.sessionID == id)
        .order(TrackPointRecord.Columns.timestamp_unix.asc)
      let cursor = try request.fetchCursor(db)

      return try GPXExportService.export(
        sessionID: id,
        sessionName: sessionName,
        cursor: cursor,
        totalCount: totalCount,
        to: url
      )
    }
  }
}
