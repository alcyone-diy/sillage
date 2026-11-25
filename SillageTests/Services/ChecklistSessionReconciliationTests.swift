//
//  ChecklistSessionReconciliationTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
import GRDB
@testable import Sillage

@MainActor
final class ChecklistSessionReconciliationTests: XCTestCase {
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

  func testUpdateTemplateUpdatesActiveSessionSnapshot() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    let template = try await catalog.createTemplate(
      title: "Pre-Sail",
      description: nil,
      categoryId: "routine",
      items: [("Check rigging", nil)]
    )

    let session = try await sessions.startSession(templateId: template.id)
    XCTAssertEqual(session.templateTitleSnapshot, "Pre-Sail")

    _ = try await catalog.updateTemplate(
      id: template.id,
      title: "Pre-Sail Rigging Check",
      description: nil,
      categoryId: "routine",
      items: [("Check rigging thoroughly", nil)]
    )

    let activeSession = try await sessions.fetchActiveSession(for: template.id)
    XCTAssertNotNil(activeSession)
    XCTAssertEqual(activeSession?.templateTitleSnapshot, "Pre-Sail Rigging Check")
  }

  func testUpdateTemplateReordersActiveSessionItemsAndPreservesCheckedState() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    let template = try await catalog.createTemplate(
      title: "Pre-Sail",
      description: nil,
      categoryId: "routine",
      items: [
        ("Check bilges", nil),
        ("Check engine oil", nil),
        ("Turn on VHF", nil)
      ]
    )

    let session = try await sessions.startSession(templateId: template.id)
    XCTAssertEqual(session.items.count, 3)
    XCTAssertEqual(session.items[0].title, "Check bilges")
    XCTAssertEqual(session.items[1].title, "Check engine oil")
    XCTAssertEqual(session.items[2].title, "Turn on VHF")

    // Check the first item ("Check bilges")
    let firstItemId = session.items[0].id
    _ = try await sessions.setItemChecked(
      sessionId: session.id,
      itemId: firstItemId,
      isChecked: true,
      coordinate: nil
    )

    // Reorder items: Step 3 first, then Step 1 (checked), then Step 2
    let reorderedItems = [
      (id: Optional(template.items[2].id), title: "Turn on VHF", detail: Optional<String>.none),
      (id: Optional(template.items[0].id), title: "Check bilges", detail: Optional<String>.none),
      (id: Optional(template.items[1].id), title: "Check engine oil", detail: Optional<String>.none)
    ]

    _ = try await catalog.updateTemplate(
      id: template.id,
      title: "Pre-Sail Reordered",
      description: nil,
      categoryId: "routine",
      items: reorderedItems
    )

    let fetchedActive = try await sessions.fetchActiveSession(for: template.id)
    let activeSession = try XCTUnwrap(fetchedActive)
    XCTAssertEqual(activeSession.items.count, 3)
    XCTAssertEqual(activeSession.items[0].title, "Turn on VHF")
    XCTAssertFalse(activeSession.items[0].isChecked)
    XCTAssertEqual(activeSession.items[0].sortOrder, 0)

    XCTAssertEqual(activeSession.items[1].title, "Check bilges")
    XCTAssertTrue(activeSession.items[1].isChecked)
    XCTAssertEqual(activeSession.items[1].sortOrder, 1)

    XCTAssertEqual(activeSession.items[2].title, "Check engine oil")
    XCTAssertFalse(activeSession.items[2].isChecked)
    XCTAssertEqual(activeSession.items[2].sortOrder, 2)
  }

  func testUpdateTemplateWithDuplicateTitleInsertedBeforeExistingPreservesStateWithoutCrash() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    // 1. Create a template with a single item and start an active session
    let template = try await catalog.createTemplate(
      title: "Valve Checks",
      description: nil,
      categoryId: "engine_technical",
      items: [
        (title: "Check valve", detail: "Original seacock")
      ]
    )
    let existingTemplateItem = try XCTUnwrap(template.items.first)
    let session = try await sessions.startSession(templateId: template.id)
    let originalSessionItem = try XCTUnwrap(session.items.first)

    // 2. Check the existing item with GPS coordinates
    let coordinate = CLLocationCoordinate2D(latitude: 47.5123, longitude: -3.1456)
    let checkedSession = try await sessions.setItemChecked(
      sessionId: session.id,
      itemId: originalSessionItem.id,
      isChecked: true,
      coordinate: coordinate
    )
    let checkedOriginalItem = try XCTUnwrap(checkedSession.items.first)
    XCTAssertTrue(checkedOriginalItem.isChecked)

    // 3. Insert a NEW item with the exact same title BEFORE the existing item
    _ = try await catalog.updateTemplate(
      id: template.id,
      title: "Valve Checks",
      description: nil,
      categoryId: "engine_technical",
      items: [
        (id: nil, title: "Check valve", detail: "New duplicate"),
        (id: existingTemplateItem.id, title: "Check valve", detail: "Original seacock")
      ]
    )

    // 4. Verify active session has both items in order without PK crash or stolen state
    let fetchedUpdatedSession = try await sessions.fetchSession(id: session.id)
    let updatedSession = try XCTUnwrap(fetchedUpdatedSession)
    XCTAssertEqual(updatedSession.items.count, 2)

    let firstItem = updatedSession.items[0]
    let secondItem = updatedSession.items[1]

    // New item at index 0 must NOT steal prior state or ID
    XCTAssertNotEqual(firstItem.id, originalSessionItem.id)
    XCTAssertEqual(firstItem.title, "Check valve")
    XCTAssertEqual(firstItem.detail, "New duplicate")
    XCTAssertFalse(firstItem.isChecked)
    XCTAssertNil(firstItem.checkedAt)
    XCTAssertNil(firstItem.coordinate)

    // Existing item at index 1 must preserve its ID, checked state, and GPS coordinates
    XCTAssertEqual(secondItem.id, originalSessionItem.id)
    XCTAssertEqual(secondItem.sourceTemplateItemId, existingTemplateItem.id)
    XCTAssertEqual(secondItem.title, "Check valve")
    XCTAssertEqual(secondItem.detail, "Original seacock")
    XCTAssertTrue(secondItem.isChecked)
    XCTAssertNotNil(secondItem.checkedAt)
    let preservedCoordinate = try XCTUnwrap(secondItem.coordinate)
    XCTAssertEqual(preservedCoordinate.latitude, coordinate.latitude, accuracy: 0.0001)
    XCTAssertEqual(preservedCoordinate.longitude, coordinate.longitude, accuracy: 0.0001)
  }

  func testDomainMapperRejectsHalfPopulatedSpatialCoordinates() throws {
    let sessionId = UUID()
    let templateId = UUID()
    let itemId = UUID()
    let now = Date()

    let sessionRecord = ChecklistSessionRecord(
      id: sessionId.uuidString,
      template_id: templateId.uuidString,
      template_title_snapshot: "Anchor Watch",
      status: ChecklistSessionStatus.inProgress.rawValue,
      started_at: now,
      completed_at: nil,
      notes: nil
    )

    let brokenItemRecord = ChecklistSessionItemRecord(
      id: itemId.uuidString,
      session_id: sessionId.uuidString,
      source_template_item_id: nil,
      sort_order: 0,
      title: "Drop anchor",
      detail: nil,
      is_checked: true,
      checked_at: now,
      latitude_deg: 47.5,
      longitude_deg: nil
    )

    do {
      _ = try ChecklistDomainMapper.mapSession(
        record: sessionRecord,
        itemRecords: [brokenItemRecord],
        categoryId: "routine"
      )
      XCTFail("Expected databaseInconsistency when only latitude is present")
    } catch {
      if case .databaseInconsistency = error {
        // Expected
      } else {
        XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testUpdateTemplateWithoutItemIdsReconcilesByTitleInFIFOOrder() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    // 1. Create a template with two homonymous steps and a third distinct step
    let template = try await catalog.createTemplate(
      title: "Seacock Checks",
      description: nil,
      categoryId: "engine_technical",
      items: [
        (title: "Inspect seacock", detail: "Engine intake"),
        (title: "Inspect seacock", detail: "Galley sink"),
        (title: "Test bilge pump", detail: "Manual switch")
      ]
    )

    let session = try await sessions.startSession(templateId: template.id)
    XCTAssertEqual(session.items.count, 3)
    let firstPriorItem = session.items[0]
    let secondPriorItem = session.items[1]

    // 2. Check ONLY the first "Inspect seacock" with GPS coordinates; leave the second unchecked
    let coordinate = CLLocationCoordinate2D(latitude: 46.1601, longitude: -1.1512)
    _ = try await sessions.setItemChecked(
      sessionId: session.id,
      itemId: firstPriorItem.id,
      isChecked: true,
      coordinate: coordinate
    )

    // 3. Update via simple tuple overload (`id == nil` on all items -> Pass 1 matches 0 items, Pass 2 FIFO runs)
    _ = try await catalog.updateTemplate(
      id: template.id,
      title: "Seacock Checks Updated",
      description: nil,
      categoryId: "engine_technical",
      items: [
        (title: "Test bilge pump", detail: "Manual + float switch"),
        (title: "Inspect seacock", detail: "Engine intake updated"),
        (title: "Inspect seacock", detail: "Galley sink updated")
      ]
    )

    // 4. Verify FIFO title matching preserved state, IDs, and GPS coordinates in exact prior order
    let fetchedUpdated = try await sessions.fetchSession(id: session.id)
    let updatedSession = try XCTUnwrap(fetchedUpdated)
    XCTAssertEqual(updatedSession.items.count, 3)

    let item0 = updatedSession.items[0]
    XCTAssertEqual(item0.title, "Test bilge pump")
    XCTAssertEqual(item0.detail, "Manual + float switch")
    XCTAssertFalse(item0.isChecked)

    let item1 = updatedSession.items[1]
    XCTAssertEqual(item1.id, firstPriorItem.id)
    XCTAssertEqual(item1.title, "Inspect seacock")
    XCTAssertEqual(item1.detail, "Engine intake updated")
    XCTAssertTrue(item1.isChecked)
    XCTAssertNotNil(item1.checkedAt)
    let preservedCoord = try XCTUnwrap(item1.coordinate)
    XCTAssertEqual(preservedCoord.latitude, coordinate.latitude, accuracy: 0.0001)
    XCTAssertEqual(preservedCoord.longitude, coordinate.longitude, accuracy: 0.0001)

    let item2 = updatedSession.items[2]
    XCTAssertEqual(item2.id, secondPriorItem.id)
    XCTAssertEqual(item2.title, "Inspect seacock")
    XCTAssertEqual(item2.detail, "Galley sink updated")
    XCTAssertFalse(item2.isChecked)
    XCTAssertNil(item2.checkedAt)
    XCTAssertNil(item2.coordinate)
  }

  func testDomainMapperResolveCategoryIdRejectsMissingTemplate() {
    let missingTemplateId = UUID().uuidString
    do {
      _ = try ChecklistDomainMapper.resolveCategoryId(
        for: missingTemplateId,
        in: ["existing": "routine"]
      )
      XCTFail("Expected databaseInconsistency when parent template is missing")
    } catch {
      if case .databaseInconsistency = error {
        // Expected
      } else {
        XCTFail("Unexpected error: \(error)")
      }
    }
  }
}
