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
  private var isolatedDefaults: IsolatedUserDefaults!

  override func setUp() async throws {
    try await super.setUp()
    isolatedDefaults = IsolatedUserDefaults(prefix: "ChecklistCategoryTests")
    databaseManager = try DatabaseManager.inMemory()
    checklistService = ChecklistService(
      databaseManager: databaseManager,
      throttler: ChecklistThrottler(window: .zero),
      userDefaults: isolatedDefaults.defaults
    )
  }

  override func tearDown() async throws {
    isolatedDefaults?.tearDown()
    isolatedDefaults = nil
    checklistService = nil
    databaseManager = nil
    try await super.tearDown()
  }

  // MARK: - Category Pre-population & Schema Tests

  func testDefaultCategoriesPrepopulated() async throws {
    let categories = try await checklistService.fetchCategories()
    let expectedIds = ["safety_emergency", "navigation_maneuver", "routine", "engine_technical", "wintering_maintenance"]
    XCTAssertEqual(categories.count, expectedIds.count)

    let ids = Set(categories.map(\.id))
    for expectedId in expectedIds {
      XCTAssertTrue(ids.contains(expectedId))
    }

    let routine = try XCTUnwrap(categories.first(where: { $0.id == "routine" }))
    XCTAssertFalse(routine.name.isEmpty)
    XCTAssertEqual(routine.icon, "checklist")
  }

  func testSeederRunsOnlyOnceAndDoesNotRecreateDeletedCategories() async throws {
    let suiteName = "ChecklistSeederTests_\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    // Clear categories in DB first
    try await databaseManager.write { db in
      try db.execute(sql: "DELETE FROM checklist_category")
    }

    // 1. First seed populates categories and sets UserDefaults flag
    try await databaseManager.write { db in
      guard let suiteDefaults = UserDefaults(suiteName: suiteName) else { return }
      try ChecklistSeeder.seedDefaultCategoriesIfNeeded(in: db, userDefaults: suiteDefaults)
    }
    XCTAssertTrue(defaults.bool(forKey: ChecklistSeeder.hasSeededInitialCategoriesKey))

    let categoriesAfterFirstSeed = try await checklistService.fetchCategories()
    XCTAssertEqual(categoriesAfterFirstSeed.count, 5)
    let routine = try XCTUnwrap(categoriesAfterFirstSeed.first(where: { $0.id == "routine" }))
    XCTAssertEqual(routine.name, String(localized: "Routine"))

    // 2. Delete a category
    try await checklistService.deleteCategory(id: "routine")
    let afterDelete = try await checklistService.fetchCategories()
    XCTAssertEqual(afterDelete.count, 4)

    // 3. Second seed is a no-op and does NOT recreate the deleted category
    try await databaseManager.write { db in
      guard let suiteDefaults = UserDefaults(suiteName: suiteName) else { return }
      try ChecklistSeeder.seedDefaultCategoriesIfNeeded(in: db, userDefaults: suiteDefaults)
    }
    let afterSecondSeed = try await checklistService.fetchCategories()
    XCTAssertEqual(afterSecondSeed.count, 4)
    XCTAssertNil(afterSecondSeed.first(where: { $0.id == "routine" }))
  }

  func testSeedDefaultTemplatesFallsBackToFirstCategoryWhenPreferredDeleted() async throws {
    let suiteName = "ChecklistSeederFallbackTests_\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    // Mark categories as already seeded, and delete "routine" from DB
    defaults.set(true, forKey: ChecklistSeeder.hasSeededInitialCategoriesKey)
    try await checklistService.deleteCategory(id: "routine")

    try await databaseManager.write { db in
      guard let suiteDefaults = UserDefaults(suiteName: suiteName) else { return }
      try ChecklistSeeder.seedDefaultTemplatesIfNeeded(in: db, userDefaults: suiteDefaults)
    }

    let templates = try await checklistService.fetchTemplates()
    XCTAssertEqual(templates.count, 4)
    let departure = try XCTUnwrap(templates.first(where: { $0.title == "Pre-Departure Checklist" }))
    // "routine" was deleted, so it must fall back to the first available category ("safety_emergency")
    XCTAssertEqual(departure.categoryId, "safety_emergency")
  }

  func testSeedDefaultTemplatesSkipsWhenNoCategoriesExist() async throws {
    let suiteName = "ChecklistSeederEmptyCategoriesTests_\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    // Mark categories as already seeded and wipe all categories from DB
    defaults.set(true, forKey: ChecklistSeeder.hasSeededInitialCategoriesKey)
    try await databaseManager.write { db in
      try db.execute(sql: "DELETE FROM checklist_category")
    }

    // Should not throw or recreate categories
    try await databaseManager.write { db in
      guard let suiteDefaults = UserDefaults(suiteName: suiteName) else { return }
      try ChecklistSeeder.seedDefaultTemplatesIfNeeded(in: db, userDefaults: suiteDefaults)
    }

    let categories = try await checklistService.fetchCategories()
    XCTAssertTrue(categories.isEmpty)
    let templates = try await checklistService.fetchTemplates()
    XCTAssertTrue(templates.isEmpty)
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

  func testFetchChecklistCountsByCategory() async throws {
    _ = try await checklistService.createCustomTemplate(
      title: "Routine 1",
      description: nil,
      categoryId: "routine",
      items: [("Item 1", nil)]
    )
    _ = try await checklistService.createCustomTemplate(
      title: "Routine 2",
      description: nil,
      categoryId: "routine",
      items: [("Item 2", nil)]
    )
    _ = try await checklistService.createCustomTemplate(
      title: "Safety 1",
      description: nil,
      categoryId: "safety_emergency",
      items: [("Item 3", nil)]
    )

    let counts = try await checklistService.fetchChecklistCountsByCategory()
    XCTAssertEqual(counts["routine"], 2)
    XCTAssertEqual(counts["safety_emergency"], 1)
    XCTAssertNil(counts["engine_technical"])
  }

  func testReorderCategoriesPersistsNewOrder() async throws {
    let initial = try await checklistService.fetchCategories()
    let reversedIds = Array(initial.map(\.id).reversed())

    try await checklistService.reorderCategories(ids: reversedIds)

    let reordered = try await checklistService.fetchCategories()
    XCTAssertEqual(reordered.map(\.id), reversedIds)
    for (expectedOrder, category) in reordered.enumerated() {
      XCTAssertEqual(category.sortOrder, expectedOrder)
    }
  }
}
