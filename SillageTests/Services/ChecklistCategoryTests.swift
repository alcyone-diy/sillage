//
//  ChecklistCategoryTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import GRDB
@testable import Sillage

@MainActor
final class ChecklistCategoryTests: XCTestCase {
  private var databaseManager: DatabaseManager!
  private var checklistService: ChecklistService!

  override func setUp() async throws {
    try await super.setUp()
    databaseManager = try DatabaseManager.inMemory()
    checklistService = ChecklistService(
      databaseManager: databaseManager,
      throttler: ChecklistThrottler(window: .zero)
    )
  }

  override func tearDown() async throws {
    checklistService = nil
    databaseManager = nil
    try await super.tearDown()
  }

  // MARK: - Category Pre-population & Schema Tests

  func testDefaultCategoriesPrepopulatedInV2() async throws {
    let categories = try await checklistService.fetchCategories()
    let expectedIds = ["safety_emergency", "navigation_maneuver", "routine", "engine_technical", "wintering_maintenance"]
    XCTAssertEqual(categories.count, expectedIds.count)

    let ids = Set(categories.map(\.id))
    for expectedId in expectedIds {
      XCTAssertTrue(ids.contains(expectedId))
    }

    let routine = try XCTUnwrap(categories.first(where: { $0.id == "routine" }))
    XCTAssertEqual(routine.name, "Routine")
    XCTAssertEqual(routine.icon, "checklist")
  }

  // MARK: - Association & Relationship Tests

  func testTemplateHasCategoryIdSynchronized() async throws {
    let template = try await checklistService.createCustomTemplate(
      title: "Engine Pre-Start",
      description: "Checks before starting engine",
      categoryId: "engine_technical",
      items: [("Check oil", "Dipstick")]
    )

    XCTAssertEqual(template.categoryId, "engine_technical")

    // Direct database verification
    let templateId = template.id.uuidString
    let record = try await databaseManager.reader.read { db in
      try ChecklistTemplateRecord.fetchOne(db, key: templateId)
    }
    let unwrappedRecord = try XCTUnwrap(record)
    XCTAssertEqual(unwrappedRecord.category_id, "engine_technical")
  }

  func testCannotDeleteCategoryWithAssociatedTemplatesViaService() async throws {
    _ = try await checklistService.createCustomTemplate(
      title: "Routine Morning Check",
      description: nil,
      categoryId: "routine",
      items: [("Deck inspection", nil)]
    )

    do {
      try await checklistService.deleteCategory(id: "routine")
      XCTFail("Expected categoryHasAssociatedTemplates error")
    } catch let error as ChecklistSessionError {
      XCTAssertEqual(error, .categoryHasAssociatedTemplates("routine"))
    }
  }

  func testCannotDeleteCategoryWithAssociatedTemplatesAtDatabaseLevel() async throws {
    _ = try await checklistService.createCustomTemplate(
      title: "Safety Gear Check",
      description: nil,
      categoryId: "safety_emergency",
      items: [("Flares", nil)]
    )

    do {
      try await databaseManager.write { db in
        try db.execute(
          sql: "DELETE FROM checklist_category WHERE id = ?",
          arguments: ["safety_emergency"]
        )
      }
      XCTFail("Expected SQLite foreign key RESTRICT constraint to fail")
    } catch {
      // Foreign key constraint failure expected
      let message = error.localizedDescription.lowercased()
      XCTAssertTrue(message.contains("foreign key") || message.contains("constraint"))
    }
  }

  func testCanDeleteCategoryWithoutAssociatedTemplates() async throws {
    let customCat = try await checklistService.createCategory(
      id: "temporary_ops",
      name: "Temporary Ops",
      icon: "flag",
      sortOrder: 10
    )

    let fetchedBefore = try await checklistService.fetchCategory(id: customCat.id)
    XCTAssertNotNil(fetchedBefore)

    try await checklistService.deleteCategory(id: customCat.id)

    let fetchedAfter = try await checklistService.fetchCategory(id: customCat.id)
    XCTAssertNil(fetchedAfter)
  }

  func testCannotInsertTemplateWithInvalidCategoryForeignKey() async throws {
    do {
      try await databaseManager.write { db in
        let now = Date()
        let invalidRecord = ChecklistTemplateRecord(
          id: UUID().uuidString,
          title: "Ghost Category Template",
          description: nil,
          category_id: "non_existent_category",
          sort_order: 0,
          created_at: now,
          updated_at: now
        )
        try invalidRecord.insert(db)
      }
      XCTFail("Expected foreign key constraint violation")
    } catch {
      let message = error.localizedDescription.lowercased()
      XCTAssertTrue(message.contains("foreign key") || message.contains("constraint"))
    }
  }

  // MARK: - Migration v1 to v2 Test

  func testMigrationFromV1ToV2PreservesDataAndEnforcesRelation() async throws {
    let queue = try DatabaseQueue()

    // 1. Create a partial migrator with only v1
    var v1Migrator = DatabaseMigrator()
    v1Migrator.registerMigration("v1") { db in
      try db.create(table: "checklist_template") { t in
        t.column("id", .text).primaryKey()
        t.column("title", .text).notNull()
        t.column("description", .text)
        t.column("category", .text).notNull()
        t.column("sort_order", .integer).notNull().defaults(to: 0)
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
      }
    }
    try v1Migrator.migrate(queue)

    // 2. Insert templates into v1 schema
    let now = Date()
    try await queue.write { db in
      try db.execute(
        sql: """
        INSERT INTO checklist_template (id, title, description, category, sort_order, created_at, updated_at)
        VALUES ('tpl-1', 'Legacy Routine', 'Desc', 'routine', 0, ?, ?)
        """,
        arguments: [now, now]
      )
      try db.execute(
        sql: """
        INSERT INTO checklist_template (id, title, description, category, sort_order, created_at, updated_at)
        VALUES ('tpl-2', 'Legacy MOB', 'Desc', 'safety_emergency', 1, ?, ?)
        """,
        arguments: [now, now]
      )
    }

    // 3. Run full migrator (v1 + v2)
    var fullMigrator = DatabaseMigrator()
    fullMigrator.registerMigration("v1") { _ in } // Already applied
    fullMigrator.registerMigration("v2") { db in
      // Apply the same decoupled v2 migration as in DatabaseManager
      try db.create(table: "checklist_category") { t in
        t.column("id", .text).primaryKey()
        t.column("name", .text).notNull()
        t.column("icon", .text)
        t.column("sort_order", .integer).notNull().defaults(to: 0)
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
      }
      try db.create(
        index: "idx_checklist_category_sort_order",
        on: "checklist_category",
        columns: ["sort_order"]
      )

      let initialCategories: [(id: String, name: String, icon: String?, sortOrder: Int)] = [
        ("safety_emergency", "Safety & Emergency", "exclamationmark.shield.fill", 0),
        ("navigation_maneuver", "Navigation & Maneuver", "steeringwheel", 1),
        ("routine", "Routine", "checklist", 2),
        ("engine_technical", "Engine & Technical", "wrench.and.screwdriver.fill", 3),
        ("wintering_maintenance", "Wintering & Maintenance", "snowflake", 4)
      ]

      for cat in initialCategories {
        try db.execute(
          sql: """
          INSERT OR IGNORE INTO checklist_category (id, name, icon, sort_order, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
          arguments: [cat.id, cat.name, cat.icon, cat.sortOrder, now, now]
        )
      }

      try db.alter(table: "checklist_template") { t in
        t.add(column: "category_id", .text)
          .references("checklist_category", column: "id", onDelete: .restrict)
      }

      try db.execute(sql: """
        UPDATE checklist_template
        SET category_id = category
        WHERE category_id IS NULL
      """)
    }
    try fullMigrator.migrate(queue)

    // 4. Verify migrated rows have category_id correctly populated
    try await queue.read { db in
      let row1 = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT category, category_id FROM checklist_template WHERE id = 'tpl-1'"))
      XCTAssertEqual(row1["category"], "routine")
      XCTAssertEqual(row1["category_id"], "routine")

      let row2 = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT category, category_id FROM checklist_template WHERE id = 'tpl-2'"))
      XCTAssertEqual(row2["category"], "safety_emergency")
      XCTAssertEqual(row2["category_id"], "safety_emergency")
    }
  }

  // MARK: - Category CRUD Tests

  func testCategoryCRUD() async throws {
    // Create
    let created = try await checklistService.createCategory(
      id: "docking",
      name: "Docking & Mooring",
      icon: "ferry",
      sortOrder: 5
    )
    XCTAssertEqual(created.id, "docking")
    XCTAssertEqual(created.name, "Docking & Mooring")
    XCTAssertEqual(created.icon, "ferry")
    XCTAssertEqual(created.sortOrder, 5)

    // Read
    let fetched = try await checklistService.fetchCategory(id: "docking")
    XCTAssertEqual(fetched?.name, "Docking & Mooring")

    // Update
    let updated = try await checklistService.updateCategory(
      id: "docking",
      name: "Harbor & Docking",
      icon: "ferry.fill",
      sortOrder: 6
    )
    XCTAssertEqual(updated.name, "Harbor & Docking")
    XCTAssertEqual(updated.icon, "ferry.fill")
    XCTAssertEqual(updated.sortOrder, 6)

    // Delete
    try await checklistService.deleteCategory(id: "docking")
    let afterDelete = try await checklistService.fetchCategory(id: "docking")
    XCTAssertNil(afterDelete)
  }

  // MARK: - Migration v2 to v3 Test

  func testMigrationFromV2ToV3DropsCategoryColumn() async throws {
    let queue = try DatabaseQueue()

    // 1. Run migrations v1 and v2
    var v2Migrator = DatabaseMigrator()
    v2Migrator.registerMigration("v1") { db in
      try db.create(table: "checklist_template") { t in
        t.column("id", .text).primaryKey()
        t.column("title", .text).notNull()
        t.column("description", .text)
        t.column("category", .text).notNull()
        t.column("sort_order", .integer).notNull().defaults(to: 0)
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
      }
      try db.create(index: "idx_checklist_template_category", on: "checklist_template", columns: ["category"])
    }
    v2Migrator.registerMigration("v2") { db in
      try db.create(table: "checklist_category") { t in
        t.column("id", .text).primaryKey()
        t.column("name", .text).notNull()
        t.column("icon", .text)
        t.column("sort_order", .integer).notNull().defaults(to: 0)
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
      }
      try db.alter(table: "checklist_template") { t in
        t.add(column: "category_id", .text)
          .references("checklist_category", column: "id", onDelete: .restrict)
      }
      try db.execute(sql: "UPDATE checklist_template SET category_id = category WHERE category_id IS NULL")
    }
    try v2Migrator.migrate(queue)

    // 2. Insert data in v2 schema
    let now = Date()
    try await queue.write { db in
      try db.execute(
        sql: "INSERT INTO checklist_category (id, name, sort_order, created_at, updated_at) VALUES ('routine', 'Routine', 0, ?, ?)",
        arguments: [now, now]
      )
      try db.execute(
        sql: """
        INSERT INTO checklist_template (id, title, description, category, category_id, sort_order, created_at, updated_at)
        VALUES ('tpl-clean', 'Clean Category', 'Desc', 'routine', 'routine', 0, ?, ?)
        """,
        arguments: [now, now]
      )
    }

    // 3. Migrate with v3
    var fullMigrator = DatabaseMigrator()
    fullMigrator.registerMigration("v1") { _ in }
    fullMigrator.registerMigration("v2") { _ in }
    fullMigrator.registerMigration("v3") { db in
      try db.execute(sql: "DROP INDEX IF EXISTS idx_checklist_template_category")
      try db.alter(table: "checklist_template") { t in
        t.drop(column: "category")
      }
    }
    try fullMigrator.migrate(queue)

    // 4. Verify category column is gone and category_id remains
    try await queue.read { db in
      let columns = try db.columns(in: "checklist_template").map(\.name)
      XCTAssertFalse(columns.contains("category"))
      XCTAssertTrue(columns.contains("category_id"))

      let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT category_id FROM checklist_template WHERE id = 'tpl-clean'"))
      XCTAssertEqual(row["category_id"], "routine")
    }
  }
}
