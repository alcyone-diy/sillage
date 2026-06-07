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
  case invalidURL
}

/// Manages the SQLite database connection and migrations using GRDB.
public final class DatabaseManager: Sendable {
  
  /// The database writer (DatabasePool for production, DatabaseQueue for in-memory tests)
  public let writer: any DatabaseWriter
  
  /// Exposes the database as a reader
  public var reader: any DatabaseReader { writer }
  
  // MARK: - Initializers
  
  /// Factory method for in-memory database (Unit Tests / Previews)
  public static func inMemory() throws -> DatabaseManager {
    // DatabaseQueue automatically creates an in-memory SQLite database
    let queue = try DatabaseQueue()
    return try DatabaseManager(writer: queue)
  }
  
  /// Internal initializer to inject the underlying writer
  private init(writer: any DatabaseWriter) throws {
    self.writer = writer
    try Self.migrator.migrate(writer)
  }
  
  /// Production initializer (Disk-based with WAL mode)
  nonisolated public init(url: URL? = nil) throws {
    let dbURL: URL
    
    if let providedURL = url {
      guard providedURL.isFileURL else { throw DatabaseError.invalidURL }
      let directoryURL = providedURL.deletingLastPathComponent()
      try Self.createDirectoryIfNeeded(at: directoryURL)
      dbURL = providedURL
    } else {
      let fileManager = FileManager.default
      guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        Logger.database.fault("Application Support directory is unreachable")
        throw DatabaseError.directoryUnreachable
      }
      let dbDirectoryURL = appSupportURL.appendingPathComponent("Database", isDirectory: true)
      try Self.createDirectoryIfNeeded(at: dbDirectoryURL)
      dbURL = dbDirectoryURL.appendingPathComponent("sillage.sqlite")
    }
    
    var configuration = Configuration()
    configuration.maximumReaderCount = 5
    configuration.prepareDatabase { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")
    }
    
    do {
      let pool = try DatabasePool(path: dbURL.path, configuration: configuration)
      self.writer = pool
      try Self.migrator.migrate(pool)
      Logger.database.info("Successfully initialized database at \(dbURL.path, privacy: .public)")
    } catch {
      Logger.database.fault("Failed to initialize database: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }
  
  nonisolated private static func createDirectoryIfNeeded(at url: URL) throws {
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: url.path) {
      try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [
        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
      ])
    }
  }
  
  nonisolated private static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    
    migrator.registerMigration("v1") { db in
      // 1. Create the session table first
      try db.create(table: "track_session") { t in
        t.column("id", .text).primaryKey()
        t.column("startTimestamp_unix", .double).notNull()
        t.column("endTimestamp_unix", .double)
        t.column("name", .text)
        t.column("description", .text)
        t.column("startLocation", .text)
        t.column("endLocation", .text)
        t.column("totalDuration_s", .double)
        t.column("totalDistanceOverGround_m", .double)
        t.column("southLatitude_deg", .double)
        t.column("northLatitude_deg", .double)
        t.column("westLongitude_deg", .double)
        t.column("eastLongitude_deg", .double)
        t.column("maxSpeedOverGround_mps", .double)
        t.column("segmentCount", .integer).notNull()
        t.column("totalPointCount", .integer).notNull()
        t.column("color_hex", .text)

        t.check(sql: "southLatitude_deg BETWEEN -90 AND 90")
        t.check(sql: "northLatitude_deg BETWEEN -90 AND 90")
        t.check(sql: "southLatitude_deg <= northLatitude_deg")
        t.check(sql: "westLongitude_deg BETWEEN -180 AND 180")
        t.check(sql: "eastLongitude_deg BETWEEN -180 AND 180")
        // Should have no constraints between westLongitude_deg and eastLongitude_deg,
        // since a track can start at 179º, and move up to -179.
        t.check(sql: "totalDuration_s >= 0")
        t.check(sql: "totalDistanceOverGround_m >= 0")
        t.check(sql: "maxSpeedOverGround_mps >= 0")
        t.check(sql: "segmentCount >= 0")
        t.check(sql: "totalPointCount >= 0")
      }
      try db.create(index: "idx_track_session_startTimestamp", on: "track_session", columns: ["startTimestamp_unix"])
      try db.create(index: "idx_track_session_name", on: "track_session", columns: ["name"])
      try db.create(index: "idx_track_session_endTimestamp_unix", on: "track_session", columns: ["endTimestamp_unix"])
      
      // 2. Create the point table with foreign key
      try db.create(table: "track_point") { t in
        // DO NOT use composite PK (sessionID + timestamp). Auto-incremented ID is required
        // for SQLite ROWID performance, SwiftUI Identifiable conformance, and to prevent
        // crashes on duplicate CoreLocation timestamps.
        t.autoIncrementedPrimaryKey("id")
        t.column("sessionID", .text)
          .notNull()
          .references("track_session", column: "id", onDelete: .cascade)
        t.column("segmentIndex", .integer).notNull()
        t.column("timestamp_unix", .double).notNull()
        t.column("latitude_deg", .double).notNull()
        t.column("longitude_deg", .double).notNull()
        t.column("horizontalAccuracy_m", .double).notNull()
        t.column("speedOverGround_mps", .double)
        t.column("courseOverGround_deg", .double)
        
        t.check(sql: "latitude_deg BETWEEN -90 AND 90")
        t.check(sql: "longitude_deg BETWEEN -180 AND 180")
        t.check(sql: "horizontalAccuracy_m >= 0")
        t.check(sql: "(courseOverGround_deg >= 0 AND courseOverGround_deg < 360) OR courseOverGround_deg IS NULL")
        t.check(sql: "speedOverGround_mps >= 0 OR speedOverGround_mps IS NULL")
      }
      
      // 3. Create the index on the Database instance (db), outside the table definition.
      try db.create(
        index: "idx_track_point_sessionId_timestamp_unix",
        on: "track_point",
        columns: ["sessionID", "timestamp_unix"]
      )
      try db.create(
        index: "idx_track_point_track_sessionId_segmentIndex_timestamp_unix",
        on: "track_point",
        columns: ["sessionID", "segmentIndex", "timestamp_unix"]
      )
      
      // 4. Create the waypoint table
      try db.create(table: "waypoint") { t in
        t.column("id", .text).primaryKey()
        t.column("name", .text).notNull()
        t.column("description", .text)
        t.column("symbol", .text)
        t.column("color_hex", .text)
        t.column("isVisible", .boolean).notNull().defaults(to: true)
        t.column("latitude_deg", .double).notNull()
        t.column("longitude_deg", .double).notNull()
        t.column("timestamp_unix", .double).notNull()
        
        t.check(sql: "latitude_deg BETWEEN -90 AND 90")
        t.check(sql: "longitude_deg BETWEEN -180 AND 180")
      }
      
      // 5. Create indexes for the waypoint table
      try db.create(index: "idx_waypoint_name", on: "waypoint", columns: ["name"])
      try db.create(index: "idx_waypoint_timestamp_unix", on: "waypoint", columns: ["timestamp_unix"])
    }
    
    return migrator
  }
}

// MARK: - Database Extensions

extension DatabaseManager {
  
  /// Performs database writes in a transaction.
  nonisolated public func write<T>(_ updates: @escaping @Sendable (Database) throws -> T) async throws -> T where T: Sendable {
    try await self.writer.write(updates)
  }
  
  func sanitizeUnfinishedSessions(excluding activeSessionID: String?) async throws {
    try await self.writer.write { db in
      // 1. Update unfinished sessions with the true last point timestamp.
      var updateQuery = TrackSessionRecord.filter(TrackSessionRecord.Columns.endTimestamp_unix == nil)
      if let activeID = activeSessionID {
        updateQuery = updateQuery.filter(TrackSessionRecord.Columns.id != activeID)
      }
      try updateQuery.updateAll(
        db,
        [TrackSessionRecord.Columns.endTimestamp_unix.set(
          to: SQL("(SELECT MAX(timestamp_unix) FROM track_point WHERE sessionID = track_session.id)")
        )]
      )
      // 2. Delete empty ghost sessions without points.
      var deleteQuery = TrackSessionRecord.having(TrackSessionRecord.trackPoints.isEmpty)
      if let activeID = activeSessionID {
        deleteQuery = deleteQuery.filter(TrackSessionRecord.Columns.id != activeID)
      }
      let deletedCount = try deleteQuery.deleteAll(db)
      if deletedCount > 0 {
        Logger.database.info("Cleanup done : \(deletedCount) ghost session(s) deleted.")
      }
    }
  }
  
  /// Fetches the highest segment index for a given session. Returns nil if no points exist.
  func fetchMaxSegmentIndex(for sessionID: String) async throws -> Int? {
    try await self.reader.read { db in
      try Int.fetchOne(db, TrackPointRecord
        .select(max(TrackPointRecord.Columns.segmentIndex))
        .filter(TrackPointRecord.Columns.sessionID == sessionID)
      )
    }
  }
  
  /// Fetches the precise Date of the last recorded point for a given session.
  func fetchLastPointTime(for sessionID: String) async throws -> Date? {
    try await self.reader.read { db in
      if let maxTimestamp = try Double.fetchOne(db, TrackPointRecord
        .select(max(TrackPointRecord.Columns.timestamp_unix))
        .filter(TrackPointRecord.Columns.sessionID == sessionID)) {
        return Date(timeIntervalSince1970: maxTimestamp)
      }
      return nil
    }
  }
  
  /// Fetches the most recent points to repopulate the RAM buffer after a crash.
  func fetchRecentPoints(for sessionID: String, limit: Int) async throws -> [TrackPoint] {
    try await self.reader.read { db in
      let records = try TrackPointRecord
        .filter(TrackPointRecord.Columns.sessionID == sessionID)
        .order(TrackPointRecord.Columns.timestamp_unix.desc)
        .limit(limit)
        .fetchAll(db)
      return records.reversed().map { $0.domainModel }
    }
  }
}
