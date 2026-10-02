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
  nonisolated public let writer: any DatabaseWriter
  
  /// Exposes the database as a reader
  nonisolated public var reader: any DatabaseReader { writer }
  
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
  
  nonisolated static var migrator: DatabaseMigrator {
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

    migrator.registerMigration("v2") { db in
      guard try !db.tableExists(BarometricReadingRecord.databaseTableName) else { return }
      // Create the barometric reading table for weather telemetry history
      try db.create(table: BarometricReadingRecord.databaseTableName) { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("timestamp_unix", .double).notNull()
        t.column("pressure_hpa", .double).notNull()
      }
      
      // Index for efficient time-range queries (1h, 3h, 24h, custom DateInterval) and pruning
      try db.create(
        index: "idx_barometric_reading_timestamp_unix",
        on: BarometricReadingRecord.databaseTableName,
        columns: ["timestamp_unix"]
      )
    }

    migrator.registerMigration("v3") { db in
      // Ensure clean state if tables existed from unversioned migration in development
      if try db.tableExists("checklist_execution_item") {
        try db.drop(table: "checklist_execution_item")
      }
      if try db.tableExists("checklist_execution") {
        try db.drop(table: "checklist_execution")
      }
      if try db.tableExists(ChecklistSessionItemRecord.databaseTableName) {
        try db.drop(table: ChecklistSessionItemRecord.databaseTableName)
      }
      if try db.tableExists(ChecklistSessionRecord.databaseTableName) {
        try db.drop(table: ChecklistSessionRecord.databaseTableName)
      }
      if try db.tableExists(ChecklistTemplateItemRecord.databaseTableName) {
        try db.drop(table: ChecklistTemplateItemRecord.databaseTableName)
      }
      if try db.tableExists(ChecklistTemplateRecord.databaseTableName) {
        try db.drop(table: ChecklistTemplateRecord.databaseTableName)
      }

      // 1. Checklist Templates
      try db.create(table: ChecklistTemplateRecord.databaseTableName) { t in
        t.column("id", .text).primaryKey()
        t.column("title", .text).notNull()
        t.column("description", .text)
        t.column("category", .text).notNull()
        t.column("sort_order", .integer).notNull().defaults(to: 0)
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
      }
      try db.create(index: "idx_checklist_template_category", on: ChecklistTemplateRecord.databaseTableName, columns: ["category"])
      try db.create(index: "idx_checklist_template_sort_order", on: ChecklistTemplateRecord.databaseTableName, columns: ["sort_order"])

      // 2. Checklist Template Items
      try db.create(table: ChecklistTemplateItemRecord.databaseTableName) { t in
        t.column("id", .text).primaryKey()
        t.column("template_id", .text)
          .notNull()
          .references(ChecklistTemplateRecord.databaseTableName, column: "id", onDelete: .cascade)
        t.column("sort_order", .integer).notNull()
        t.column("title", .text).notNull()
        t.column("detail", .text)
      }
      try db.create(
        index: "idx_checklist_template_item_template_order",
        on: ChecklistTemplateItemRecord.databaseTableName,
        columns: ["template_id", "sort_order"]
      )

      // 3. Checklist Sessions (CASCADE deletion if template is deleted)
      try db.create(table: ChecklistSessionRecord.databaseTableName) { t in
        t.column("id", .text).primaryKey()
        t.column("template_id", .text)
          .notNull()
          .references(ChecklistTemplateRecord.databaseTableName, column: "id", onDelete: .cascade)
        t.column("template_title_snapshot", .text).notNull()
        t.column("status", .text).notNull()
        t.column("started_at", .datetime).notNull()
        t.column("completed_at", .datetime)
        t.column("notes", .text)

        t.check(sql: "status IN ('in_progress', 'completed', 'abandoned')")
      }
      try db.create(index: "idx_checklist_session_status", on: ChecklistSessionRecord.databaseTableName, columns: ["status"])
      try db.create(index: "idx_checklist_session_started_at", on: ChecklistSessionRecord.databaseTableName, columns: ["started_at"])

      // Partial unique index guaranteeing only one in-progress execution per template
      try db.create(
        index: "idx_unique_active_session",
        on: ChecklistSessionRecord.databaseTableName,
        columns: ["template_id"],
        unique: true,
        condition: SQL("status = 'in_progress'")
      )

      // 4. Checklist Session Items
      try db.create(table: ChecklistSessionItemRecord.databaseTableName) { t in
        t.column("id", .text).primaryKey()
        t.column("execution_id", .text)
          .notNull()
          .references(ChecklistSessionRecord.databaseTableName, column: "id", onDelete: .cascade)
        t.column("source_template_item_id", .text)
        t.column("sort_order", .integer).notNull()
        t.column("title", .text).notNull()
        t.column("detail", .text)
        t.column("is_checked", .boolean).notNull().defaults(to: false)
        t.column("checked_at", .datetime)
        t.column("latitude_deg", .double)
        t.column("longitude_deg", .double)

        // Enforce spatial atomicity: either both coordinates are present or neither
        t.check(sql: "(latitude_deg IS NULL) = (longitude_deg IS NULL)")
        t.check(sql: "latitude_deg IS NULL OR (latitude_deg BETWEEN -90 AND 90)")
        t.check(sql: "longitude_deg IS NULL OR (longitude_deg BETWEEN -180 AND 180)")
      }
      try db.create(
        index: "idx_checklist_session_item_execution_order",
        on: ChecklistSessionItemRecord.databaseTableName,
        columns: ["execution_id", "sort_order"]
      )
    }

    migrator.registerMigration("v4") { db in
      let hasOldExecution = try db.tableExists("checklist_execution")
      let hasOldItems = try db.tableExists("checklist_execution_item")
      let hasSessionItemsReferencingOldTable = try {
        guard try db.tableExists(ChecklistSessionItemRecord.databaseTableName) else { return false }
        let rows = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list('\(ChecklistSessionItemRecord.databaseTableName)')")
        return rows.contains { ($0["table"] as? String) == "checklist_execution" }
      }()

      if hasOldExecution || hasOldItems || hasSessionItemsReferencingOldTable {
        // 1. Create checklist_session if needed and copy rows from checklist_execution
        if try !db.tableExists(ChecklistSessionRecord.databaseTableName) {
          try db.create(table: ChecklistSessionRecord.databaseTableName) { t in
            t.column("id", .text).primaryKey()
            t.column("template_id", .text)
              .notNull()
              .references(ChecklistTemplateRecord.databaseTableName, column: "id", onDelete: .cascade)
            t.column("template_title_snapshot", .text).notNull()
            t.column("status", .text).notNull()
            t.column("started_at", .datetime).notNull()
            t.column("completed_at", .datetime)
            t.column("notes", .text)

            t.check(sql: "status IN ('in_progress', 'completed', 'abandoned')")
          }

          if hasOldExecution {
            try db.execute(sql: """
              INSERT INTO \(ChecklistSessionRecord.databaseTableName)
              (id, template_id, template_title_snapshot, status, started_at, completed_at, notes)
              SELECT id, template_id, template_title_snapshot, status, started_at, completed_at, notes
              FROM checklist_execution
            """)
          }

          try db.create(index: "idx_checklist_session_status", on: ChecklistSessionRecord.databaseTableName, columns: ["status"])
          try db.create(index: "idx_checklist_session_started_at", on: ChecklistSessionRecord.databaseTableName, columns: ["started_at"])
          try db.create(
            index: "idx_unique_active_session",
            on: ChecklistSessionRecord.databaseTableName,
            columns: ["template_id"],
            unique: true,
            condition: SQL("status = 'in_progress'")
          )
        }

        // 2. Recreate checklist_session_item pointing to checklist_session
        let sourceItemTable: String? = try {
          if try db.tableExists("checklist_execution_item") {
            return "checklist_execution_item"
          } else if try db.tableExists(ChecklistSessionItemRecord.databaseTableName) {
            return ChecklistSessionItemRecord.databaseTableName
          }
          return nil
        }()

        if let sourceTable = sourceItemTable {
          let tempItemTable = "checklist_session_item_migrated"
          if try db.tableExists(tempItemTable) {
            try db.drop(table: tempItemTable)
          }

          try db.create(table: tempItemTable) { t in
            t.column("id", .text).primaryKey()
            t.column("execution_id", .text)
              .notNull()
              .references(ChecklistSessionRecord.databaseTableName, column: "id", onDelete: .cascade)
            t.column("source_template_item_id", .text)
            t.column("sort_order", .integer).notNull()
            t.column("title", .text).notNull()
            t.column("detail", .text)
            t.column("is_checked", .boolean).notNull().defaults(to: false)
            t.column("checked_at", .datetime)
            t.column("latitude_deg", .double)
            t.column("longitude_deg", .double)

            t.check(sql: "(latitude_deg IS NULL) = (longitude_deg IS NULL)")
            t.check(sql: "latitude_deg IS NULL OR (latitude_deg BETWEEN -90 AND 90)")
            t.check(sql: "longitude_deg IS NULL OR (longitude_deg BETWEEN -180 AND 180)")
          }

          try db.execute(sql: """
            INSERT INTO \(tempItemTable)
            (id, execution_id, source_template_item_id, sort_order, title, detail, is_checked, checked_at, latitude_deg, longitude_deg)
            SELECT id, execution_id, source_template_item_id, sort_order, title, detail, is_checked, checked_at, latitude_deg, longitude_deg
            FROM \(sourceTable)
            WHERE execution_id IN (SELECT id FROM \(ChecklistSessionRecord.databaseTableName))
          """)

          try db.drop(table: sourceTable)

          if try db.tableExists(ChecklistSessionItemRecord.databaseTableName) {
            try db.drop(table: ChecklistSessionItemRecord.databaseTableName)
          }

          try db.rename(table: tempItemTable, to: ChecklistSessionItemRecord.databaseTableName)

          try db.create(
            index: "idx_checklist_session_item_execution_order",
            on: ChecklistSessionItemRecord.databaseTableName,
            columns: ["execution_id", "sort_order"]
          )
        }

        // 3. Drop checklist_execution safely now that all child references are migrated or dropped
        if try db.tableExists("checklist_execution") {
          try db.drop(table: "checklist_execution")
        }
      }
    }

    migrator.registerMigration("v5") { db in
      func safeCreateIndex(
        name: String,
        on table: String,
        columns: [String],
        unique: Bool = false,
        condition: SQL? = nil
      ) throws {
        try db.execute(sql: "DROP INDEX IF EXISTS \(name)")
        try db.create(
          index: name,
          on: table,
          columns: columns,
          unique: unique,
          condition: condition
        )
      }

      // 1. Ensure Checklist Templates and Items exist defensively
      if try !db.tableExists(ChecklistTemplateRecord.databaseTableName) {
        try db.create(table: ChecklistTemplateRecord.databaseTableName) { t in
          t.column("id", .text).primaryKey()
          t.column("title", .text).notNull()
          t.column("description", .text)
          t.column("category", .text).notNull()
          t.column("sort_order", .integer).notNull().defaults(to: 0)
          t.column("created_at", .datetime).notNull()
          t.column("updated_at", .datetime).notNull()
        }
        try safeCreateIndex(
          name: "idx_checklist_template_category",
          on: ChecklistTemplateRecord.databaseTableName,
          columns: ["category"]
        )
        try safeCreateIndex(
          name: "idx_checklist_template_sort_order",
          on: ChecklistTemplateRecord.databaseTableName,
          columns: ["sort_order"]
        )
      }

      if try !db.tableExists(ChecklistTemplateItemRecord.databaseTableName) {
        try db.create(table: ChecklistTemplateItemRecord.databaseTableName) { t in
          t.column("id", .text).primaryKey()
          t.column("template_id", .text)
            .notNull()
            .references(ChecklistTemplateRecord.databaseTableName, column: "id", onDelete: .cascade)
          t.column("sort_order", .integer).notNull()
          t.column("title", .text).notNull()
          t.column("detail", .text)
        }
        try safeCreateIndex(
          name: "idx_checklist_template_item_template_order",
          on: ChecklistTemplateItemRecord.databaseTableName,
          columns: ["template_id", "sort_order"]
        )
      }

      // 2. Ensure Checklist Sessions exist and safely transfer legacy executions
      if try !db.tableExists(ChecklistSessionRecord.databaseTableName) {
        try db.create(table: ChecklistSessionRecord.databaseTableName) { t in
          t.column("id", .text).primaryKey()
          t.column("template_id", .text)
            .notNull()
            .references(ChecklistTemplateRecord.databaseTableName, column: "id", onDelete: .cascade)
          t.column("template_title_snapshot", .text).notNull()
          t.column("status", .text).notNull()
          t.column("started_at", .datetime).notNull()
          t.column("completed_at", .datetime)
          t.column("notes", .text)

          t.check(sql: "status IN ('in_progress', 'completed', 'abandoned')")
        }
      }

      // Transfer any unmigrated execution records even if checklist_session already exists
      if try db.tableExists("checklist_execution") {
        try db.execute(sql: """
          INSERT OR IGNORE INTO \(ChecklistSessionRecord.databaseTableName)
          (id, template_id, template_title_snapshot, status, started_at, completed_at, notes)
          SELECT id, template_id, template_title_snapshot, status, started_at, completed_at, notes
          FROM checklist_execution
        """)
      }

      try safeCreateIndex(
        name: "idx_checklist_session_status",
        on: ChecklistSessionRecord.databaseTableName,
        columns: ["status"]
      )
      try safeCreateIndex(
        name: "idx_checklist_session_started_at",
        on: ChecklistSessionRecord.databaseTableName,
        columns: ["started_at"]
      )
      try safeCreateIndex(
        name: "idx_unique_active_session",
        on: ChecklistSessionRecord.databaseTableName,
        columns: ["template_id"],
        unique: true,
        condition: SQL("status = 'in_progress'")
      )

      // 3. Ensure Checklist Session Items exist and recreate if pointing to old execution table
      let hasSessionItemsReferencingOldTable = try {
        guard try db.tableExists(ChecklistSessionItemRecord.databaseTableName) else { return false }
        let rows = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list('\(ChecklistSessionItemRecord.databaseTableName)')")
        return rows.contains { ($0["table"] as? String) == "checklist_execution" }
      }()

      var primarySourceWasOldTable = false

      if try !db.tableExists(ChecklistSessionItemRecord.databaseTableName) || hasSessionItemsReferencingOldTable {
        let tempItemTable = "checklist_session_item_migrated"
        if try db.tableExists(tempItemTable) {
          try db.drop(table: tempItemTable)
        }

        try db.create(table: tempItemTable) { t in
          t.column("id", .text).primaryKey()
          t.column("execution_id", .text)
            .notNull()
            .references(ChecklistSessionRecord.databaseTableName, column: "id", onDelete: .cascade)
          t.column("source_template_item_id", .text)
          t.column("sort_order", .integer).notNull()
          t.column("title", .text).notNull()
          t.column("detail", .text)
          t.column("is_checked", .boolean).notNull().defaults(to: false)
          t.column("checked_at", .datetime)
          t.column("latitude_deg", .double)
          t.column("longitude_deg", .double)

          t.check(sql: "(latitude_deg IS NULL) = (longitude_deg IS NULL)")
          t.check(sql: "latitude_deg IS NULL OR (latitude_deg BETWEEN -90 AND 90)")
          t.check(sql: "longitude_deg IS NULL OR (longitude_deg BETWEEN -180 AND 180)")
        }

        // Prioritize the newer checklist_session_item table first
        let sourceTable: String? = try {
          if try db.tableExists(ChecklistSessionItemRecord.databaseTableName) {
            return ChecklistSessionItemRecord.databaseTableName
          } else if try db.tableExists("checklist_execution_item") {
            primarySourceWasOldTable = true
            return "checklist_execution_item"
          }
          return nil
        }()

        if let sourceTable = sourceTable {
          try db.execute(sql: """
            INSERT INTO \(tempItemTable)
            (id, execution_id, source_template_item_id, sort_order, title, detail, is_checked, checked_at, latitude_deg, longitude_deg)
            SELECT id, execution_id, source_template_item_id, sort_order, title, detail, is_checked, checked_at, latitude_deg, longitude_deg
            FROM \(sourceTable)
            WHERE execution_id IN (SELECT id FROM \(ChecklistSessionRecord.databaseTableName))
          """)
        }

        if try db.tableExists(ChecklistSessionItemRecord.databaseTableName) {
          try db.drop(table: ChecklistSessionItemRecord.databaseTableName)
        }

        try db.rename(table: tempItemTable, to: ChecklistSessionItemRecord.databaseTableName)
      }

      // Recover any unmigrated items from checklist_execution_item without overwriting newer items.
      // Only executes as a safety net if the primary source was not already checklist_execution_item.
      if !primarySourceWasOldTable, try db.tableExists("checklist_execution_item") {
        try db.execute(sql: """
          INSERT OR IGNORE INTO \(ChecklistSessionItemRecord.databaseTableName)
          (id, execution_id, source_template_item_id, sort_order, title, detail, is_checked, checked_at, latitude_deg, longitude_deg)
          SELECT id, execution_id, source_template_item_id, sort_order, title, detail, is_checked, checked_at, latitude_deg, longitude_deg
          FROM checklist_execution_item
          WHERE execution_id IN (SELECT id FROM \(ChecklistSessionRecord.databaseTableName))
        """)
      }

      try safeCreateIndex(
        name: "idx_checklist_session_item_execution_order",
        on: ChecklistSessionItemRecord.databaseTableName,
        columns: ["execution_id", "sort_order"]
      )

      // 4. Drop legacy execution tables safely now that all sessions and items are migrated
      if try db.tableExists("checklist_execution_item") {
        try db.drop(table: "checklist_execution_item")
      }
      if try db.tableExists("checklist_execution") {
        try db.drop(table: "checklist_execution")
      }
    }

    migrator.registerMigration("v6") { db in
      guard try !db.tableExists("geogarage_download") else { return }

      try db.create(table: "geogarage_download") { t in
        t.column("id", .text).primaryKey()
        t.column("layer_id", .text).notNull()
        t.column("layer_name", .text).notNull()
        t.column("download_timestamp_unix", .double).notNull()
        t.column("relative_path", .text).notNull()
        t.column("md5", .text).notNull()
        t.column("zoom_max", .integer).notNull()
        t.column("bounds_wkt", .text).notNull()
        t.column("custom_name", .text)
        t.column("file_size_bytes", .integer)

        t.check(sql: "zoom_max >= 0")
        t.check(sql: "file_size_bytes IS NULL OR file_size_bytes >= 0")
      }

      try db.create(
        index: "idx_geogarage_download_layer_id",
        on: "geogarage_download",
        columns: ["layer_id"]
      )

      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_geogarage_download_layer_date
        ON geogarage_download (layer_id, download_timestamp_unix DESC)
      """)
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
