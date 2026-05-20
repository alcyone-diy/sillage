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
import SwiftUI

private struct TrackServiceKey: EnvironmentKey {
  static let defaultValue: TrackService? = nil
}

public extension EnvironmentValues {
  var trackService: TrackService? {
    get { self[TrackServiceKey.self] }
    set { self[TrackServiceKey.self] = newValue }
  }
}

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
}
