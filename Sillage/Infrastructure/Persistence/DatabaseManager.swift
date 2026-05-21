//
//  DatabaseManager.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-10.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB
import OSLog

public enum DatabaseError: Error {
  case directoryUnreachable
}

/// Manages the SQLite database connection and migrations using GRDB.
public final class DatabaseManager: Sendable {
    
  /// The database pool for concurrent reads and writes (WAL mode).
  public let dbPool: DatabasePool
  
  /// Initializes the database manager. Throws an error to be handled by the App state.
  nonisolated public init() throws {
    let fileManager = FileManager.default
    guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      Logger.database.fault("Application Support directory is unreachable")
      throw DatabaseError.directoryUnreachable
    }
    
    let dbDirectoryURL = appSupportURL.appendingPathComponent("Database", isDirectory: true)
    
    if !fileManager.fileExists(atPath: dbDirectoryURL.path) {
      try fileManager.createDirectory(at: dbDirectoryURL, withIntermediateDirectories: true, attributes: [
        // Allows background writing when the device is locked
        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
      ])
    }
    
    let dbURL = dbDirectoryURL.appendingPathComponent("sillage.sqlite")
    
    var configuration = Configuration()
    configuration.maximumReaderCount = 5
    configuration.prepareDatabase { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")
    }
    
    do {
      let pool = try DatabasePool(path: dbURL.path, configuration: configuration)
      try Self.migrator.migrate(pool)
      self.dbPool = pool
      Logger.database.info("Successfully initialized database at \(dbURL.path, privacy: .public)")
    } catch {
      Logger.database.fault("Failed to initialize database: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }
  
  nonisolated private static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    
    migrator.registerMigration("v1") { db in
      // 1. Create the session table first
      try db.create(table: "track_session") { t in
        t.column("id", .text).primaryKey()
        t.column("startTime_unix", .double).notNull()
        t.column("endTime_unix", .double)
        t.column("name", .text)
        t.column("description", .text)
        t.column("duration_s", .double)
        t.column("totalDistance_m", .double)
        t.column("minLatitude_deg", .double)
        t.column("maxLatitude_deg", .double)
        t.column("minLongitude_deg", .double)
        t.column("maxLongitude_deg", .double)
        t.column("maxSpeed_mps", .double)
        t.column("pointsCount", .integer)
        t.column("segmentCount", .integer)

        t.check(sql: "minLatitude_deg BETWEEN -90 AND 90")
        t.check(sql: "maxLatitude_deg BETWEEN -90 AND 90")
        t.check(sql: "minLatitude_deg <= maxLatitude_deg")
        t.check(sql: "minLongitude_deg BETWEEN -180 AND 180")
        t.check(sql: "maxLongitude_deg BETWEEN -180 AND 180")
        // Should have no constraints between minLongitude_deg and maxLongitude_deg,
        // since a track can start at 179º, and move up to -179.
        t.check(sql: "duration_s >= 0")
        t.check(sql: "totalDistance_m >= 0")
        t.check(sql: "maxSpeed_mps >= 0 OR maxSpeed_mps IS NULL")
        t.check(sql: "pointsCount >= 0 OR pointsCount IS NULL")
        t.check(sql: "segmentCount >= 0 OR segmentCount IS NULL")
      }
      try db.create(index: "idx_track_session_startTime", on: "track_session", columns: ["startTime_unix"])
      try db.create(index: "idx_track_session_name", on: "track_session", columns: ["name"])

      // 2. Create the point table with foreign key
      try db.create(table: "track_point") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("sessionId", .text)
          .notNull()
          .references("track_session", column: "id", onDelete: .cascade)
        t.column("segmentIndex", .integer).notNull()
        t.column("timestamp_unix", .double).notNull()
        t.column("latitude_deg", .double).notNull()
        t.column("longitude_deg", .double).notNull()
        t.column("horizontalAccuracy_m", .double).notNull()
        t.column("sog_mps", .double)
        t.column("cog_deg", .double)

        t.check(sql: "latitude_deg BETWEEN -90 AND 90")
        t.check(sql: "longitude_deg BETWEEN -180 AND 180")
        t.check(sql: "horizontalAccuracy_m >= 0")
        t.check(sql: "cog_deg BETWEEN 0 AND 360 OR cog_deg IS NULL")
        t.check(sql: "sog_mps >= 0 OR sog_mps IS NULL")
      }
      
      // 3. Create the index on the Database instance (db), outside the table definition
      try db.create(
        index: "idx_track_point_session_timestamp",
        on: "track_point",
        columns: ["sessionId", "segmentIndex", "timestamp_unix"]
      )
    }
    
    return migrator
  }
}

// MARK: - Database Extensions

extension DatabaseManager {
  /// Exposes the database pool as a reader.
  nonisolated public var reader: DatabaseReader { dbPool }

  /// Performs database writes in a transaction.
  nonisolated public func write<T>(_ updates: @escaping @Sendable (Database) throws -> T) async throws -> T where T: Sendable {
    try await dbPool.write(updates)
  }
}
