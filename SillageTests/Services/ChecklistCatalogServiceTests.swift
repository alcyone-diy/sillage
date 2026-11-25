//
//  ChecklistCatalogServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import GRDB
@testable import Sillage

@MainActor
final class ChecklistCatalogServiceTests: XCTestCase {
  private var databaseManager: DatabaseManager?
  private var catalogService: ChecklistCatalogService?
  private var sessionService: ChecklistSessionService?

  override func setUp() async throws {
    try await super.setUp()
    let db = try DatabaseManager.inMemory()
    databaseManager = db
    catalogService = ChecklistCatalogService(databaseManager: db)
    sessionService = ChecklistSessionService(
      databaseManager: db,
      throttler: ChecklistThrottler(window: .zero)
    )
  }

  override func tearDown() async throws {
    sessionService = nil
    catalogService = nil
    databaseManager = nil
    try await super.tearDown()
  }

  // MARK: - Seeding Tests

  func testDefaultSeeding() async throws {
    let catalog = try XCTUnwrap(catalogService)
    try await catalog.seedDefaultTemplatesIfNeeded()

    let templates = try await catalog.fetchTemplates()
    XCTAssertEqual(templates.count, 4)

    // Second call should be a no-op
    try await catalog.seedDefaultTemplatesIfNeeded()
    let templatesAfterSecondSeed = try await catalog.fetchTemplates()
    XCTAssertEqual(templatesAfterSecondSeed.count, 4)
  }

  // MARK: - Template Operations Tests

  func testCreateAndFetchTemplate() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let items = [
      ("Check fuel tank", "Minimum 50% capacity"),
      ("Stow fenders", Optional<String>.none)
    ]

    let created = try await catalog.createTemplate(
      title: "Night Sailing Prep",
      description: "Night passage checklist",
      categoryId: "routine",
      items: items
    )

    XCTAssertEqual(created.title, "Night Sailing Prep")
    XCTAssertEqual(created.categoryId, "routine")
    XCTAssertEqual(created.items.count, 2)
    XCTAssertEqual(created.items[0].title, "Check fuel tank")

    let fetched = try await catalog.fetchTemplate(id: created.id)
    XCTAssertNotNil(fetched)
    XCTAssertEqual(fetched?.id, created.id)
    XCTAssertEqual(fetched?.items.count, 2)
  }

  func testDeleteTemplateWithoutHistory() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let template = try await catalog.createTemplate(
      title: "Temporary Checklist",
      description: nil,
      categoryId: "engine_technical",
      items: [("Check belt", nil)]
    )

    try await catalog.deleteTemplate(id: template.id)
    let fetched = try await catalog.fetchTemplate(id: template.id)
    XCTAssertNil(fetched)
  }

  func testCanDeleteSystemTemplateWithoutHistory() async throws {
    let catalog = try XCTUnwrap(catalogService)
    try await catalog.seedDefaultTemplatesIfNeeded()
    let templates = try await catalog.fetchTemplates()
    let template = try XCTUnwrap(templates.first)

    try await catalog.deleteTemplate(id: template.id)
    let fetched = try await catalog.fetchTemplate(id: template.id)
    XCTAssertNil(fetched)
  }

  func testDeleteTemplateWithHistoryCascades() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)
    let dbManager = try XCTUnwrap(databaseManager)

    try await catalog.seedDefaultTemplatesIfNeeded()
    let templates = try await catalog.fetchTemplates()
    let template = try XCTUnwrap(templates.first)

    // Start a session to create history
    let session = try await sessions.startSession(templateId: template.id)

    try await catalog.deleteTemplate(id: template.id)

    let fetchedTemplate = try await catalog.fetchTemplate(id: template.id)
    XCTAssertNil(fetchedTemplate)

    let fetchedSession = try await sessions.fetchSession(id: session.id)
    XCTAssertNil(fetchedSession)

    let templateIdString = template.id.uuidString
    let remainingTemplateItems = try await dbManager.reader.read { db in
      try ChecklistTemplateItemRecord
        .filter(ChecklistTemplateItemRecord.Columns.template_id == templateIdString)
        .fetchCount(db)
    }
    XCTAssertEqual(remainingTemplateItems, 0)

    let sessionIdString = session.id.uuidString
    let remainingSessionItems = try await dbManager.reader.read { db in
      try ChecklistSessionItemRecord
        .filter(ChecklistSessionItemRecord.Columns.session_id == sessionIdString)
        .fetchCount(db)
    }
    XCTAssertEqual(remainingSessionItems, 0)
  }

  func testDeleteTemplateWithAbandonedHistoryCascades() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    let template = try await catalog.createTemplate(
      title: "History Protected",
      description: nil,
      categoryId: "routine",
      items: [("Item", nil)]
    )

    let session = try await sessions.startSession(templateId: template.id)
    _ = try await sessions.abandonSession(sessionId: session.id)

    try await catalog.deleteTemplate(id: template.id)

    let fetchedTemplate = try await catalog.fetchTemplate(id: template.id)
    XCTAssertNil(fetchedTemplate)

    let fetchedSession = try await sessions.fetchSession(id: session.id)
    XCTAssertNil(fetchedSession)
  }

  func testCanUpdateDefaultTemplate() async throws {
    let catalog = try XCTUnwrap(catalogService)
    try await catalog.seedDefaultTemplatesIfNeeded()
    let templates = try await catalog.fetchTemplates()
    let template = try XCTUnwrap(templates.first)

    let updated = try await catalog.updateTemplate(
      id: template.id,
      title: "Modified Checklist",
      description: "User customized",
      categoryId: "routine",
      items: [(id: nil, title: "Custom Step 1", detail: "Custom Detail")]
    )

    XCTAssertEqual(updated.title, "Modified Checklist")
    XCTAssertEqual(updated.items.count, 1)

    let fetched = try await catalog.fetchTemplate(id: template.id)
    XCTAssertEqual(fetched?.title, "Modified Checklist")
  }

  func testDeletedTemplatesDoNotReseedOnRestart() async throws {
    let catalog = try XCTUnwrap(catalogService)
    try await catalog.seedDefaultTemplatesIfNeeded()
    let templates = try await catalog.fetchTemplates()
    XCTAssertEqual(templates.count, 4)

    for template in templates {
      try await catalog.deleteTemplate(id: template.id)
    }
    let afterDelete = try await catalog.fetchTemplates()
    XCTAssertEqual(afterDelete.count, 0)

    // Calling seedDefaultTemplatesIfNeeded again must not recreate deleted templates
    try await catalog.seedDefaultTemplatesIfNeeded()
    let afterReseedAttempt = try await catalog.fetchTemplates()
    XCTAssertEqual(afterReseedAttempt.count, 0)
  }

  func testUpdateTemplateNotFound() async throws {
    let catalog = try XCTUnwrap(catalogService)
    do {
      _ = try await catalog.updateTemplate(
        id: UUID(),
        title: "Ghost",
        description: nil,
        categoryId: "routine",
        items: [("Ghost step", nil)]
      )
      XCTFail("Expected error when updating non-existent template")
    } catch ChecklistError.templateNotFound {
      // Expected
    }
  }
}
