//
//  WaypointService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB
import OSLog

/// A thread-safe service providing read and write operations for waypoints in the database.
public struct WaypointService: Sendable {
  private let databaseManager: DatabaseManager
  
  public init(databaseManager: DatabaseManager) {
    self.databaseManager = databaseManager
  }
  
  /// Observes saved waypoints, ordered by timestamp descending, in real-time.
  /// - Returns: An AsyncSequence emitting arrays of `Waypoint` whenever the database updates.
  public func observeWaypoints() -> some AsyncSequence<[Waypoint], Error> {
    let observation = ValueObservation.tracking { db in
      let records = try WaypointRecord
        .order(WaypointRecord.Columns.timestamp_unix.desc)
        .fetchAll(db)
      
      return records.map { $0.toDomain() }
    }
    
    return observation.values(in: databaseManager.reader)
  }
  
  /// Fetches all waypoints in the database.
  /// - Returns: An array of `Waypoint`.
  public func fetchWaypoints() async throws -> [Waypoint] {
    try await databaseManager.reader.read { db in
      let records = try WaypointRecord
        .order(WaypointRecord.Columns.timestamp_unix.desc)
        .fetchAll(db)
      return records.map { $0.toDomain() }
    }
  }
  
  /// Saves a waypoint to the database. Inserts or updates existing.
  public func saveWaypoint(_ waypoint: Waypoint) async throws {
    _ = try await databaseManager.write { db in
      let record = WaypointRecord(domainModel: waypoint)
      try record.save(db)
      Logger.database.info("Successfully saved waypoint: \(waypoint.id, privacy: .public)")
    }
  }
  
  /// Deletes a waypoint from the database by its ID.
  public func deleteWaypoint(id: String) async throws {
    _ = try await databaseManager.write { db in
      let deleted = try WaypointRecord.deleteOne(db, key: id)
      if deleted {
        Logger.database.info("Successfully deleted waypoint: \(id, privacy: .public)")
      } else {
        Logger.database.warning("Waypoint not found for deletion: \(id, privacy: .public)")
      }
    }
  }
}
