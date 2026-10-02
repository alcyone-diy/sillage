//
//  DatabaseManagerTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
import GRDB
import CoreLocation
@testable import Sillage

@Suite("Database Manager Tests")
final class DatabaseManagerTests {
  let dbManager: DatabaseManager
  
  init() throws {
    dbManager = try DatabaseManager.inMemory()
  }
  
  // MARK: - Tests
  
  @Test("sanitizeUnfinishedSessions updates end time and deletes empty sessions")
  func testSanitizeUnfinishedSessions() async throws {
    let now = Date(timeIntervalSince1970: 0)
    
    // 1. Session with points but no endTimestamp (should be updated)
    let session1Id = "session-1"
    let session1 = TrackSessionRecord(id: session1Id, startTime: now.addingTimeInterval(-1000))
    let point1 = makeTrackPoint(
      sessionID: session1Id,
      timestamp: now.addingTimeInterval(-500)
    )
    
    // 2. Session without points (should be deleted)
    let session2Id = "session-2"
    let session2 = TrackSessionRecord(id: session2Id, startTime: now.addingTimeInterval(-2000))
    
    // 3. Active session without points (should NOT be deleted because it is excluded)
    let session3Id = "session-3-active"
    let session3 = TrackSessionRecord(id: session3Id, startTime: now.addingTimeInterval(-3000))
    
    try await dbManager.write { db in
      try session1.insert(db)
      try point1.insert(db)
      try session2.insert(db)
      try session3.insert(db)
    }
    
    // Perform sanitization, excluding session3
    try await dbManager.sanitizeUnfinishedSessions(excluding: session3Id)
    
    // Verify session1 has updated endTimestamp
    let updatedSession1 = try await dbManager.reader.read { db in
      try TrackSessionRecord.fetchOne(db, key: session1Id)
    }
    #expect(updatedSession1 != nil)
    #expect(updatedSession1?.endTimestamp_unix != nil)
    #expect(updatedSession1?.endTimestamp_unix == point1.timestamp_unix)
    
    // Verify session2 was deleted
    let session2Exists = try await dbManager.reader.read { db in
      try TrackSessionRecord.exists(db, key: session2Id)
    }
    #expect(!session2Exists)
    
    // Verify session3 was kept (excluded)
    let session3Exists = try await dbManager.reader.read { db in
      try TrackSessionRecord.exists(db, key: session3Id)
    }
    #expect(session3Exists)
  }
  
  @Test("fetchMaxSegmentIndex returns correct max index")
  func testFetchMaxSegmentIndex() async throws {
    let sessionID = "session-1"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    // Empty session should return nil
    let emptyIndex = try await dbManager.fetchMaxSegmentIndex(for: sessionID)
    #expect(emptyIndex == nil)
    
    // Add points with different segment indices
    let point0 = makeTrackPoint(
      sessionID: sessionID,
      timestamp: Date(timeIntervalSince1970: 0),
      segmentIndex: 0
    )
    let point2 = makeTrackPoint(
      sessionID: sessionID,
      timestamp: Date(timeIntervalSince1970: 10),
      segmentIndex: 2
    )
    try await dbManager.write { db in
      try point0.insert(db)
      try point2.insert(db)
    }
    
    let maxIndex = try await dbManager.fetchMaxSegmentIndex(for: sessionID)
    #expect(maxIndex == 2)
  }
  
  @Test("fetchLastPointTime returns precise Date of the last point")
  func testFetchLastPointTime() async throws {
    let sessionID = "session-1"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    // Empty session should return nil
    let emptyTime = try await dbManager.fetchLastPointTime(for: sessionID)
    #expect(emptyTime == nil)
    
    let time1 = Date(timeIntervalSince1970: 10)
    let time2 = Date(timeIntervalSince1970: 10.001)
    
    let point1 = makeTrackPoint(
      sessionID: sessionID,
      timestamp: time1
    )
    let point2 = makeTrackPoint(
      sessionID: sessionID,
      timestamp: time2
    )
    
    try await dbManager.write { db in
      try point1.insert(db)
      try point2.insert(db)
    }
    
    let lastTime = try await dbManager.fetchLastPointTime(for: sessionID)
    if let lastTime = lastTime {
      #expect(abs(lastTime.timeIntervalSince(time2)) < 0.0001)
    } else {
      Issue.record("lastTime should not be nil")
    }
  }
  
  @Test("fetchRecentPoints returns most recent points within limit")
  func testFetchRecentPoints() async throws {
    let sessionID = "session-1"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    // Insert 5 points sequentially
    try await dbManager.write { db in
      for i in 0..<5 {
        let point = self.makeTrackPoint(
          sessionID: sessionID,
          timestamp: Date(timeIntervalSince1970: TimeInterval(1000 + i * 10))
        )
        try point.insert(db)
      }
    }
    
    // Fetch with limit 3
    let recentPoints = try await dbManager.fetchRecentPoints(for: sessionID, limit: 3)
    
    #expect(recentPoints.count == 3)
    // Should be oldest of the recent ones first (chronological order)
    let timestamp0 = await recentPoints[0].timestamp
    let timestamp1 = await recentPoints[1].timestamp
    let timestamp2 = await recentPoints[2].timestamp
    #expect(timestamp0.timeIntervalSince1970 == 1020)
    #expect(timestamp1.timeIntervalSince1970 == 1030)
    #expect(timestamp2.timeIntervalSince1970 == 1040)
  }
  
  @Test("Cascade deletion removes all associated points")
  func testCascadeDeletionRemovesAllAssociatedPoints() async throws {
    let sessionID = "session-cascade"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    // Insert 5 points sequentially
    try await dbManager.write { db in
      for i in 0..<5 {
        let point = self.makeTrackPoint(
          sessionID: sessionID,
          timestamp: Date(timeIntervalSince1970: TimeInterval(1000 + i * 10))
        )
        try point.insert(db)
      }
    }
    
    // Verify 5 points exist
    let pointCountBefore = try await dbManager.reader.read { db in
      try TrackPointRecord.fetchCount(db)
    }
    #expect(pointCountBefore == 5)
    
    // Delete the session
    try await dbManager.write { db in
      _ = try session.delete(db)
    }
    
    // Check that the points table is empty
    let pointCountAfter = try await dbManager.reader.read { db in
      try TrackPointRecord.fetchCount(db)
    }
    #expect(pointCountAfter == 0)
  }
  
  @Test("Concurrent track point insertions")
  func testConcurrentTrackPointInsertions() async throws {
    let sessionID = "session-concurrent"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    let manager = self.dbManager
    
    // Insert 100 points concurrently
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<100 {
        let point = self.makeTrackPoint(
          sessionID: sessionID,
          timestamp: Date(timeIntervalSince1970: TimeInterval(1000 + i))
        )
        
        group.addTask {
          try await manager.write { db in
            try point.insert(db)
          }
        }
      }
      
      // Wait for all tasks to finish to propagate any potential errors
      for try await _ in group {}
    }
    
    // Verify that totalPointCount is exactly 100 at the end
    let totalPointCount = try await manager.reader.read { db in
      try TrackPointRecord.fetchCount(db)
    }
    #expect(totalPointCount == 100)
  }
  
  @Test("Database constraints reject invalid coordinates")
  func testDatabaseConstraintsRejectInvalidCoordinates() async throws {
    let sessionID = "session-invalid-coord"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    let invalidPoint = TrackPointRecord(
      id: nil,
      sessionID: sessionID,
      timestamp: Date(),
      segmentIndex: 0,
      coordinate: CLLocationCoordinate2D(latitude: 91.0, longitude: 0.0),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters)
    )
    
    await #expect(throws: GRDB.DatabaseError.self) {
      try await dbManager.write { db in
        try invalidPoint.insert(db)
      }
    }
  }

  @Test("v4 migration properly migrates checklist_execution to checklist_session without foreign key violation")
  func testV4MigrationFromChecklistExecution() throws {
    let queue = try DatabaseQueue()

    // 1. Setup pre-v4 database state with v1, v2, v3 applied and old tables existing
    try queue.write { db in
      try db.execute(sql: """
        CREATE TABLE grdb_migrations (
          identifier TEXT NOT NULL PRIMARY KEY
        );
        INSERT INTO grdb_migrations VALUES ('v1'), ('v2'), ('v3');
      """)

      try db.create(table: ChecklistTemplateRecord.databaseTableName) { t in
        t.column("id", .text).primaryKey()
        t.column("title", .text).notNull()
        t.column("description", .text)
        t.column("category", .text).notNull()
        t.column("sort_order", .integer).notNull().defaults(to: 0)
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
      }

      try db.create(table: "checklist_execution") { t in
        t.column("id", .text).primaryKey()
        t.column("template_id", .text)
          .notNull()
          .references(ChecklistTemplateRecord.databaseTableName, column: "id", onDelete: .cascade)
        t.column("template_title_snapshot", .text).notNull()
        t.column("status", .text).notNull()
        t.column("started_at", .datetime).notNull()
        t.column("completed_at", .datetime)
        t.column("notes", .text)
      }

      try db.create(table: "checklist_execution_item") { t in
        t.column("id", .text).primaryKey()
        t.column("execution_id", .text)
          .notNull()
          .references("checklist_execution", column: "id", onDelete: .cascade)
        t.column("source_template_item_id", .text)
        t.column("sort_order", .integer).notNull()
        t.column("title", .text).notNull()
        t.column("detail", .text)
        t.column("is_checked", .boolean).notNull().defaults(to: false)
        t.column("checked_at", .datetime)
        t.column("latitude_deg", .double)
        t.column("longitude_deg", .double)
      }

      let templateId = UUID().uuidString
      let executionId = UUID().uuidString
      let itemId = UUID().uuidString

      try db.execute(
        sql: "INSERT INTO checklist_template (id, title, category, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
        arguments: [templateId, "Pre-Departure", "routine", 0, Date(), Date()]
      )
      try db.execute(
        sql: "INSERT INTO checklist_execution (id, template_id, template_title_snapshot, status, started_at) VALUES (?, ?, ?, ?, ?)",
        arguments: [executionId, templateId, "Pre-Departure", "in_progress", Date()]
      )
      try db.execute(
        sql: "INSERT INTO checklist_execution_item (id, execution_id, sort_order, title, is_checked) VALUES (?, ?, ?, ?, ?)",
        arguments: [itemId, executionId, 0, "Check Bilge", false]
      )
    }

    // 2. Run DatabaseManager migrations (which executes v4 and performs foreign key check)
    let migrator = DatabaseManager.migrator
    try migrator.migrate(queue)

    // 3. Verify that new session and session item tables exist and old execution tables are gone
    try queue.read { db in
      #expect(try db.tableExists(ChecklistSessionRecord.databaseTableName))
      #expect(try db.tableExists(ChecklistSessionItemRecord.databaseTableName))
      #expect(try !db.tableExists("checklist_execution"))
      #expect(try !db.tableExists("checklist_execution_item"))

      let sessionCount = try ChecklistSessionRecord.fetchCount(db)
      let itemCount = try ChecklistSessionItemRecord.fetchCount(db)
      #expect(sessionCount == 1)
      #expect(itemCount == 1)

      let item = try ChecklistSessionItemRecord.fetchOne(db)
      #expect(item?.title == "Check Bilge")

      // Verify foreign key integrity
      let fkViolations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
      #expect(fkViolations.isEmpty)
    }
  }

  @Test("v5 migration creates missing checklist_session and checklist_session_item tables on databases stuck at v4")
  func testV5MigrationWhenChecklistSessionMissing() throws {
    let queue = try DatabaseQueue()

    // 1. Setup pre-v5 database state with v1..v4 applied, template table existing, but NO session tables
    try queue.write { db in
      try db.execute(sql: """
        CREATE TABLE grdb_migrations (
          identifier TEXT NOT NULL PRIMARY KEY
        );
        INSERT INTO grdb_migrations VALUES ('v1'), ('v2'), ('v3'), ('v4');
      """)

      try db.create(table: ChecklistTemplateRecord.databaseTableName) { t in
        t.column("id", .text).primaryKey()
        t.column("title", .text).notNull()
        t.column("description", .text)
        t.column("category", .text).notNull()
        t.column("sort_order", .integer).notNull().defaults(to: 0)
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
      }
    }

    // 2. Run DatabaseManager migrations (which executes v5)
    let migrator = DatabaseManager.migrator
    try migrator.migrate(queue)

    // 3. Verify session tables exist and can be queried without SQLite error
    try queue.read { db in
      #expect(try db.tableExists(ChecklistSessionRecord.databaseTableName))
      #expect(try db.tableExists(ChecklistSessionItemRecord.databaseTableName))

      let sessionCount = try ChecklistSessionRecord.fetchCount(db)
      let itemCount = try ChecklistSessionItemRecord.fetchCount(db)
      #expect(sessionCount == 0)
      #expect(itemCount == 0)

      let fkViolations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
      #expect(fkViolations.isEmpty)
    }
  }

  @Test("v5 migration properly migrates legacy checklist_execution on databases that skipped v4")
  func testV5MigrationMigratesLegacyChecklistExecution() throws {
    let queue = try DatabaseQueue()

    // 1. Setup pre-v5 state with v1..v4 applied but legacy execution tables still present
    try queue.write { db in
      try db.execute(sql: """
        CREATE TABLE grdb_migrations (
          identifier TEXT NOT NULL PRIMARY KEY
        );
        INSERT INTO grdb_migrations VALUES ('v1'), ('v2'), ('v3'), ('v4');
      """)

      try db.create(table: ChecklistTemplateRecord.databaseTableName) { t in
        t.column("id", .text).primaryKey()
        t.column("title", .text).notNull()
        t.column("description", .text)
        t.column("category", .text).notNull()
        t.column("sort_order", .integer).notNull().defaults(to: 0)
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
      }

      try db.create(table: "checklist_execution") { t in
        t.column("id", .text).primaryKey()
        t.column("template_id", .text)
          .notNull()
          .references(ChecklistTemplateRecord.databaseTableName, column: "id", onDelete: .cascade)
        t.column("template_title_snapshot", .text).notNull()
        t.column("status", .text).notNull()
        t.column("started_at", .datetime).notNull()
        t.column("completed_at", .datetime)
        t.column("notes", .text)
      }

      try db.create(table: "checklist_execution_item") { t in
        t.column("id", .text).primaryKey()
        t.column("execution_id", .text)
          .notNull()
          .references("checklist_execution", column: "id", onDelete: .cascade)
        t.column("source_template_item_id", .text)
        t.column("sort_order", .integer).notNull()
        t.column("title", .text).notNull()
        t.column("detail", .text)
        t.column("is_checked", .boolean).notNull().defaults(to: false)
        t.column("checked_at", .datetime)
        t.column("latitude_deg", .double)
        t.column("longitude_deg", .double)
      }

      let templateId = UUID().uuidString
      let executionId = UUID().uuidString
      let itemId = UUID().uuidString

      try db.execute(
        sql: "INSERT INTO checklist_template (id, title, category, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
        arguments: [templateId, "Routine Departure", "routine", 0, Date(), Date()]
      )
      try db.execute(
        sql: "INSERT INTO checklist_execution (id, template_id, template_title_snapshot, status, started_at) VALUES (?, ?, ?, ?, ?)",
        arguments: [executionId, templateId, "Routine Departure", "in_progress", Date()]
      )
      try db.execute(
        sql: "INSERT INTO checklist_execution_item (id, execution_id, sort_order, title, is_checked) VALUES (?, ?, ?, ?, ?)",
        arguments: [itemId, executionId, 0, "Check Engine Oil", true]
      )
    }

    // 2. Run DatabaseManager migrations (which executes v5)
    let migrator = DatabaseManager.migrator
    try migrator.migrate(queue)

    // 3. Verify data is migrated and old tables dropped
    try queue.read { db in
      #expect(try db.tableExists(ChecklistSessionRecord.databaseTableName))
      #expect(try db.tableExists(ChecklistSessionItemRecord.databaseTableName))
      #expect(try !db.tableExists("checklist_execution"))
      #expect(try !db.tableExists("checklist_execution_item"))

      let session = try ChecklistSessionRecord.fetchOne(db)
      #expect(session?.template_title_snapshot == "Routine Departure")
      #expect(session?.status == "in_progress")

      let item = try ChecklistSessionItemRecord.fetchOne(db)
      #expect(item?.title == "Check Engine Oil")
      #expect(item?.is_checked == true)

      let fkViolations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
      #expect(fkViolations.isEmpty)
    }
  }

  @Test("v5 migration preserves newer session items and handles pre-existing indexes safely")
  func testV5MigrationPreservesNewerSessionItemsAndSafeIndexes() throws {
    let queue = try DatabaseQueue()

    let templateId = UUID().uuidString
    let sessionId = UUID().uuidString
    let itemId = UUID().uuidString
    let unmigratedExecutionId = UUID().uuidString
    let unmigratedItemId = UUID().uuidString

    // 1. Setup pre-v5 state with v1..v4, pre-existing session table + legacy execution table + pre-existing index
    try queue.write { db in
      try db.execute(sql: """
        CREATE TABLE grdb_migrations (
          identifier TEXT NOT NULL PRIMARY KEY
        );
        INSERT INTO grdb_migrations VALUES ('v1'), ('v2'), ('v3'), ('v4');
      """)

      try db.create(table: ChecklistTemplateRecord.databaseTableName) { t in
        t.column("id", .text).primaryKey()
        t.column("title", .text).notNull()
        t.column("description", .text)
        t.column("category", .text).notNull()
        t.column("sort_order", .integer).notNull().defaults(to: 0)
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
      }

      // Pre-existing session table with a newer item
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
      }

      // Pre-create index to test safe index replacement
      try db.create(index: "idx_checklist_session_status", on: ChecklistSessionRecord.databaseTableName, columns: ["status"])

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
      }

      // Also create legacy execution tables with conflicting session ID and an unmigrated session
      try db.create(table: "checklist_execution") { t in
        t.column("id", .text).primaryKey()
        t.column("template_id", .text).notNull()
        t.column("template_title_snapshot", .text).notNull()
        t.column("status", .text).notNull()
        t.column("started_at", .datetime).notNull()
        t.column("completed_at", .datetime)
        t.column("notes", .text)
      }

      try db.create(table: "checklist_execution_item") { t in
        t.column("id", .text).primaryKey()
        t.column("execution_id", .text).notNull()
        t.column("source_template_item_id", .text)
        t.column("sort_order", .integer).notNull()
        t.column("title", .text).notNull()
        t.column("detail", .text)
        t.column("is_checked", .boolean).notNull()
        t.column("checked_at", .datetime)
        t.column("latitude_deg", .double)
        t.column("longitude_deg", .double)
      }

      try db.execute(
        sql: "INSERT INTO checklist_template (id, title, category, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
        arguments: [templateId, "Pre-Departure", "routine", 0, Date(), Date()]
      )

      // Newer session in checklist_session
      try db.execute(
        sql: "INSERT INTO checklist_session (id, template_id, template_title_snapshot, status, started_at) VALUES (?, ?, ?, ?, ?)",
        arguments: [sessionId, templateId, "Pre-Departure (Newer)", "in_progress", Date()]
      )
      try db.execute(
        sql: "INSERT INTO checklist_session_item (id, execution_id, sort_order, title, is_checked) VALUES (?, ?, ?, ?, ?)",
        arguments: [itemId, sessionId, 0, "Check Engine Oil", true]
      )

      // Older duplicate session in checklist_execution (should be ignored by INSERT OR IGNORE)
      try db.execute(
        sql: "INSERT INTO checklist_execution (id, template_id, template_title_snapshot, status, started_at) VALUES (?, ?, ?, ?, ?)",
        arguments: [sessionId, templateId, "Pre-Departure (Old)", "abandoned", Date()]
      )
      // Unmigrated legacy session (should be imported)
      try db.execute(
        sql: "INSERT INTO checklist_execution (id, template_id, template_title_snapshot, status, started_at) VALUES (?, ?, ?, ?, ?)",
        arguments: [unmigratedExecutionId, templateId, "Old Anchoring", "completed", Date()]
      )
      try db.execute(
        sql: "INSERT INTO checklist_execution_item (id, execution_id, sort_order, title, is_checked) VALUES (?, ?, ?, ?, ?)",
        arguments: [unmigratedItemId, unmigratedExecutionId, 0, "Set Anchor", true]
      )
    }

    // 2. Migrate
    let migrator = DatabaseManager.migrator
    try migrator.migrate(queue)

    // 3. Verify
    try queue.read { db in
      #expect(try db.tableExists(ChecklistSessionRecord.databaseTableName))
      #expect(try db.tableExists(ChecklistSessionItemRecord.databaseTableName))
      #expect(try !db.tableExists("checklist_execution"))
      #expect(try !db.tableExists("checklist_execution_item"))

      // Both sessions exist: existing one kept newer title, unmigrated one was imported
      let session1 = try ChecklistSessionRecord.fetchOne(db, key: sessionId)
      #expect(session1?.template_title_snapshot == "Pre-Departure (Newer)")
      #expect(session1?.status == "in_progress")

      let session2 = try ChecklistSessionRecord.fetchOne(db, key: unmigratedExecutionId)
      #expect(session2?.template_title_snapshot == "Old Anchoring")
      #expect(session2?.status == "completed")

      // Both items exist
      let item1 = try ChecklistSessionItemRecord.fetchOne(db, key: itemId)
      #expect(item1?.is_checked == true)

      let item2 = try ChecklistSessionItemRecord.fetchOne(db, key: unmigratedItemId)
      #expect(item2?.title == "Set Anchor")

      let fkViolations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
      #expect(fkViolations.isEmpty)
    }
  }

  @Test("Migration v6 creates geogarage_download table and indexes with DESC sort order")
  func testMigrationV6_createsTableAndIndexes() async throws {
    let queue = try DatabaseQueue()
    try DatabaseManager.migrator.migrate(queue)

    try await queue.read { db in
      #expect(try db.tableExists(GeoGarageDownloadRecord.databaseTableName))

      let indexes = try db.indexes(on: GeoGarageDownloadRecord.databaseTableName)
      let indexNames = Set(indexes.map(\.name))
      #expect(indexNames.contains("idx_geogarage_download_layer_id"))
      #expect(indexNames.contains("idx_geogarage_download_layer_date"))

      // Formally verify via PRAGMA index_xinfo that download_timestamp_unix is sorted DESC (desc == 1)
      let xinfoRows = try Row.fetchAll(db, sql: "PRAGMA index_xinfo('idx_geogarage_download_layer_date')")
      let timestampRow = xinfoRows.first { ($0["name"] as? String) == "download_timestamp_unix" }
      #expect(timestampRow != nil)
      let isDesc = (timestampRow?["desc"] as? Int) == 1 || (timestampRow?["desc"] as? Int64) == 1
      #expect(isDesc)

      // Also verify the explicit DDL definition in sqlite_master
      let masterSQL = try String.fetchOne(
        db,
        sql: "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'idx_geogarage_download_layer_date'"
      )
      #expect(masterSQL?.contains("download_timestamp_unix DESC") == true)
    }
  }

  @Test("fetchLastDownloadDate aggregates MAX timestamp in O(1) and uses index")
  func testFetchLastDownloadDate_aggregatesMaxAndUsesIndex() async throws {
    let id1 = UUID().uuidString
    let id2 = UUID().uuidString
    let id3 = UUID().uuidString

    try await dbManager.write { db in
      try GeoGarageDownloadRecord(
        id: id1,
        layer_id: "shom",
        layer_name: "SHOM 1",
        download_timestamp_unix: 1_000_000,
        relative_path: "Charts/shom1.mbtiles",
        md5: "abc1",
        zoom_max: 12,
        bounds_wkt: "POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))",
        file_size_bytes: 1024
      ).insert(db)

      try GeoGarageDownloadRecord(
        id: id2,
        layer_id: "shom",
        layer_name: "SHOM 2",
        download_timestamp_unix: 2_000_000,
        relative_path: "Charts/shom2.mbtiles",
        md5: "abc2",
        zoom_max: 14,
        bounds_wkt: "POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))",
        file_size_bytes: 2048
      ).insert(db)

      try GeoGarageDownloadRecord(
        id: id3,
        layer_id: "noaa",
        layer_name: "NOAA Raster",
        download_timestamp_unix: 1_500_000,
        relative_path: "Charts/noaa.mbtiles",
        md5: "abc3",
        zoom_max: 10,
        bounds_wkt: "POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))",
        file_size_bytes: 4096
      ).insert(db)
    }

    // Verify MAX aggregation values
    let shomDate = try await dbManager.fetchLastDownloadDate(for: "shom")
    #expect(shomDate?.timeIntervalSince1970 == 2_000_000)

    let noaaDate = try await dbManager.fetchLastDownloadDate(for: "noaa")
    #expect(noaaDate?.timeIntervalSince1970 == 1_500_000)

    let unknownDate = try await dbManager.fetchLastDownloadDate(for: "unknown")
    #expect(unknownDate == nil)

    // Verify EXPLAIN QUERY PLAN confirms index usage (O(1) B-tree lookup without table scan)
    try await dbManager.reader.read { db in
      let queryPlanRows = try Row.fetchAll(
        db,
        sql: "EXPLAIN QUERY PLAN SELECT MAX(download_timestamp_unix) FROM geogarage_download WHERE layer_id = ?",
        arguments: ["shom"]
      )
      let planDetail = queryPlanRows.map { ($0["detail"] as? String) ?? "" }.joined(separator: " ")
      #expect(planDetail.contains("idx_geogarage_download_layer_date"))
      #expect(!planDetail.contains("SCAN TABLE"))
    }
  }

  // MARK: - Helpers
  
  private func makeTrackPoint(sessionID: String, timestamp: Date, segmentIndex: Int = 0) -> TrackPointRecord {
    return TrackPointRecord(
      id: nil,
      sessionID: sessionID,
      timestamp: timestamp,
      segmentIndex: segmentIndex,
      coordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters)
    )
  }
}
