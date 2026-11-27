//
//  ChecklistSessionServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
import GRDB
@testable import Sillage

@MainActor
final class ChecklistSessionServiceTests: XCTestCase {
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

  // MARK: - Session Lifecycle & Get-or-Create Tests

  func testStartSessionAndGetOrCreate() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    let template = try await catalog.createTemplate(
      title: "Engine Start",
      description: nil,
      categoryId: "engine_technical",
      items: [
        ("Open seacock", nil),
        ("Check oil", nil)
      ]
    )

    // 1. Initial start
    let session1 = try await sessions.startSession(templateId: template.id)
    XCTAssertEqual(session1.templateId, template.id)
    XCTAssertEqual(session1.status, .inProgress)
    XCTAssertEqual(session1.items.count, 2)
    XCTAssertEqual(session1.completedCount, 0)
    XCTAssertEqual(session1.progressRatio, 0.0)

    // 2. Second start on same template -> Transparent resume (Get-or-Create)
    let session2 = try await sessions.startSession(templateId: template.id)
    XCTAssertEqual(session1.id, session2.id)
  }

  func testStartSessionThrowsTemplateNotFound() async throws {
    let sessions = try XCTUnwrap(sessionService)
    let missingId = UUID()

    do {
      _ = try await sessions.startSession(templateId: missingId)
      XCTFail("Expected templateNotFound error")
    } catch {
      XCTAssertEqual(error, .templateNotFound(missingId))
    }
  }

  func testSetItemCheckedIdempotencyAndCoordinate() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    let template = try await catalog.createTemplate(
      title: "Anchor Procedure",
      description: nil,
      categoryId: "navigation_maneuver",
      items: [
        ("Drop anchor", "Record coordinates"),
        ("Set snubber", nil)
      ]
    )

    let session = try await sessions.startSession(templateId: template.id)
    let itemToToggle = session.items[0]
    let coordinate = CLLocationCoordinate2D(latitude: 46.159, longitude: -1.152)

    // Check item with coordinate
    let updated1 = try await sessions.setItemChecked(
      sessionId: session.id,
      itemId: itemToToggle.id,
      isChecked: true,
      coordinate: coordinate
    )

    let checkedItem = updated1.items.first { $0.id == itemToToggle.id }
    XCTAssertNotNil(checkedItem)
    XCTAssertTrue(checkedItem?.isChecked == true)
    XCTAssertNotNil(checkedItem?.checkedAt)
    XCTAssertEqual(checkedItem?.coordinate?.latitude, 46.159)
    XCTAssertEqual(checkedItem?.coordinate?.longitude, -1.152)
    XCTAssertEqual(updated1.completedCount, 1)

    // Second check with isChecked: true -> Idempotent, no change
    let updated2 = try await sessions.setItemChecked(
      sessionId: session.id,
      itemId: itemToToggle.id,
      isChecked: true,
      coordinate: coordinate
    )
    XCTAssertEqual(updated1.items.first?.checkedAt, updated2.items.first?.checkedAt)

    // Uncheck item
    let updated3 = try await sessions.setItemChecked(
      sessionId: session.id,
      itemId: itemToToggle.id,
      isChecked: false,
      coordinate: nil
    )
    let uncheckedItem = updated3.items.first { $0.id == itemToToggle.id }
    XCTAssertFalse(uncheckedItem?.isChecked == true)
    XCTAssertNil(uncheckedItem?.checkedAt)
    XCTAssertNil(uncheckedItem?.coordinate)
  }

  func testDeleteSession() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    let template = try await catalog.createTemplate(
      title: "Reset Test",
      description: nil,
      categoryId: "routine",
      items: [
        ("Step 1", nil),
        ("Step 2", nil)
      ]
    )

    let session = try await sessions.startSession(templateId: template.id)
    _ = try await sessions.setItemChecked(
      sessionId: session.id,
      itemId: session.items[0].id,
      isChecked: true,
      coordinate: nil
    )

    try await sessions.deleteSession(sessionId: session.id)
    let fetched = try await sessions.fetchSession(id: session.id)
    XCTAssertNil(fetched)

    let activeSession = try await sessions.fetchActiveSession(for: template.id)
    XCTAssertNil(activeSession)

    // Complete session then delete again
    let session2 = try await sessions.startSession(templateId: template.id)
    _ = try await sessions.setItemChecked(sessionId: session2.id, itemId: session2.items[0].id, isChecked: true)
    _ = try await sessions.setItemChecked(sessionId: session2.id, itemId: session2.items[1].id, isChecked: true)
    _ = try await sessions.completeSession(sessionId: session2.id, notes: nil)

    try await sessions.deleteSession(sessionId: session2.id)
    let fetchedCompleted = try await sessions.fetchSession(id: session2.id)
    XCTAssertNil(fetchedCompleted)
  }

  func testCompleteSession() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    let template = try await catalog.createTemplate(
      title: "Completion Test",
      description: nil,
      categoryId: "safety_emergency",
      items: [
        ("Step 1", nil),
        ("Step 2", nil)
      ]
    )

    let session = try await sessions.startSession(templateId: template.id)

    _ = try await sessions.setItemChecked(
      sessionId: session.id,
      itemId: session.items[0].id,
      isChecked: true,
      coordinate: nil
    )

    let completed = try await sessions.completeSession(
      sessionId: session.id,
      notes: "Executed in 2 minutes"
    )
    XCTAssertEqual(completed.status, .completed)
    XCTAssertNotNil(completed.completedAt)
    XCTAssertEqual(completed.notes, "Executed in 2 minutes")

    // Attempting completion again should fail
    do {
      _ = try await sessions.completeSession(sessionId: session.id, notes: nil)
      XCTFail("Expected sessionAlreadyFinished error")
    } catch {
      XCTAssertEqual(error, .sessionAlreadyFinished(session.id))
    }
  }

  func testSetItemCheckedFailsOnCompletedSession() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    let template = try await catalog.createTemplate(
      title: "Completed Session Mutability Check",
      description: nil,
      categoryId: "routine",
      items: [("Task 1", nil)]
    )

    let session = try await sessions.startSession(templateId: template.id)
    _ = try await sessions.setItemChecked(
      sessionId: session.id,
      itemId: session.items[0].id,
      isChecked: true
    )
    _ = try await sessions.completeSession(sessionId: session.id)

    do {
      _ = try await sessions.setItemChecked(
        sessionId: session.id,
        itemId: session.items[0].id,
        isChecked: false
      )
      XCTFail("Expected sessionAlreadyFinished error when mutating completed session")
    } catch {
      XCTAssertEqual(error, .sessionAlreadyFinished(session.id))
    }
  }

  func testAbandonSession() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    let template = try await catalog.createTemplate(
      title: "Abandon Test",
      description: nil,
      categoryId: "routine",
      items: [("Task 1", nil)]
    )

    let session = try await sessions.startSession(templateId: template.id)
    let abandoned = try await sessions.abandonSession(sessionId: session.id)

    XCTAssertEqual(abandoned.status, .abandoned)
    XCTAssertNotNil(abandoned.completedAt)

    // Modifying an abandoned session should fail
    do {
      _ = try await sessions.setItemChecked(
        sessionId: session.id,
        itemId: session.items[0].id,
        isChecked: true,
        coordinate: nil
      )
      XCTFail("Expected sessionAlreadyFinished error")
    } catch {
      XCTAssertEqual(error, .sessionAlreadyFinished(session.id))
    }
  }

  func testReactiveActiveSessionsObservation() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    let template = try await catalog.createTemplate(
      title: "Observation Test",
      description: nil,
      categoryId: "routine",
      items: [("Step", nil)]
    )

    let stream = sessions.observeActiveSessions()
    var iterator = stream.makeAsyncIterator()

    // 1. Initial emission: empty array
    let initial = try await iterator.next()
    XCTAssertEqual(initial?.count, 0)

    // 2. Start session
    let session = try await sessions.startSession(templateId: template.id)
    let afterStart = try await iterator.next()
    XCTAssertEqual(afterStart?.count, 1)
    XCTAssertEqual(afterStart?.first?.id, session.id)

    // 3. Complete session
    _ = try await sessions.completeSession(sessionId: session.id, notes: nil)
    let afterComplete = try await iterator.next()
    XCTAssertEqual(afterComplete?.count, 0)
  }

  func testReactiveSessionsObservation() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)
    let dbManager = try XCTUnwrap(databaseManager)

    let template = try await catalog.createTemplate(
      title: "All Sessions Observation Test",
      description: nil,
      categoryId: "routine",
      items: [("Step", nil)]
    )

    let secondTemplate = try await catalog.createTemplate(
      title: "Second Checklist",
      description: nil,
      categoryId: "safety_emergency",
      items: [("Check", nil)]
    )

    let stream = sessions.observeSessions()
    var iterator = stream.makeAsyncIterator()

    // 1. Initial emission: empty array
    let initial = try await iterator.next()
    XCTAssertEqual(initial?.count, 0)

    // 2. Start session
    let session = try await sessions.startSession(templateId: template.id)
    let afterStart = try await iterator.next()
    XCTAssertEqual(afterStart?.count, 1)
    XCTAssertEqual(afterStart?.first?.id, session.id)

    // 3. Complete session -> still present in observeSessions
    _ = try await sessions.completeSession(sessionId: session.id, notes: nil)
    let afterComplete = try await iterator.next()
    XCTAssertEqual(afterComplete?.count, 1)
    XCTAssertEqual(afterComplete?.first?.id, session.id)
    XCTAssertEqual(afterComplete?.first?.status, .completed)
    XCTAssertEqual(afterComplete?.first?.categoryId, "routine")

    // 4. Age completed session past retention threshold (e.g. 49h ago) -> excluded by frozen threshold
    let sessionIdString = session.id.uuidString
    let pastRetentionInterval = -Double(ChecklistSessionService.completedSessionRetentionHours + 1) * 3600
    try await dbManager.write { db in
      var record = try XCTUnwrap(ChecklistSessionRecord.fetchOne(db, key: sessionIdString))
      record.completed_at = Date().addingTimeInterval(pastRetentionInterval)
      try record.update(db)
    }
    let afterAging = try await iterator.next()
    XCTAssertEqual(afterAging?.count, 0)

    // 5. In-progress sessions remain included regardless of age
    _ = try await sessions.startSession(templateId: secondTemplate.id)
    let afterSecond = try await iterator.next()
    XCTAssertEqual(afterSecond?.count, 1)

    // 6. A fresh observation stream also excludes the old completed session
    let freshStream = sessions.observeSessions()
    var freshIterator = freshStream.makeAsyncIterator()
    let freshInitial = try await freshIterator.next()
    XCTAssertEqual(freshInitial?.count, 1)
  }

  func testThrottlerDebouncesRapidTaps() async throws {
    let throttler = ChecklistThrottler(window: .milliseconds(300))
    let itemId = UUID()

    // First action should pass
    let first = await throttler.shouldProcessAction(for: itemId)
    XCTAssertTrue(first)

    // Immediate second action should be debounced
    let second = await throttler.shouldProcessAction(for: itemId)
    XCTAssertFalse(second)

    // After waiting 350ms, next action should pass
    try await Task.sleep(for: .milliseconds(350))
    let third = await throttler.shouldProcessAction(for: itemId)
    XCTAssertTrue(third)
  }

  func testSetItemCheckedRejectsItemFromAnotherSession() async throws {
    let catalog = try XCTUnwrap(catalogService)
    let sessions = try XCTUnwrap(sessionService)

    let templateA = try await catalog.createTemplate(
      title: "Template A",
      items: [(title: "Item A", detail: nil)]
    )
    let templateB = try await catalog.createTemplate(
      title: "Template B",
      items: [(title: "Item B", detail: nil)]
    )

    let sessionA = try await sessions.startSession(templateId: templateA.id)
    let sessionB = try await sessions.startSession(templateId: templateB.id)
    let itemB = try XCTUnwrap(sessionB.items.first)

    do {
      _ = try await sessions.setItemChecked(
        sessionId: sessionA.id,
        itemId: itemB.id,
        isChecked: true
      )
      XCTFail("Expected itemNotFound when passing an itemId belonging to another session")
    } catch {
      XCTAssertEqual(error, .itemNotFound(itemB.id))
    }

    // Verify neither session was modified
    let fetchedA = try await sessions.fetchSession(id: sessionA.id)
    let fetchedB = try await sessions.fetchSession(id: sessionB.id)
    let reloadedA = try XCTUnwrap(fetchedA)
    let reloadedB = try XCTUnwrap(fetchedB)
    XCTAssertFalse(try XCTUnwrap(reloadedA.items.first).isChecked)
    XCTAssertFalse(try XCTUnwrap(reloadedB.items.first).isChecked)
  }

  func testThrottlerResetsOnWriteErrorAllowingImmediateRetry() async throws {
    let db = try XCTUnwrap(databaseManager)
    let catalog = try XCTUnwrap(catalogService)
    let strictSessionService = ChecklistSessionService(
      databaseManager: db,
      throttler: ChecklistThrottler(window: .seconds(10))
    )

    let template = try await catalog.createTemplate(
      title: "Throttler Reset Check",
      items: [(title: "Bilge pump", detail: nil)]
    )
    let session = try await strictSessionService.startSession(templateId: template.id)
    let item = try XCTUnwrap(session.items.first)

    // 1. Trigger an error using the item's ID with a nonexistent sessionId
    let nonexistentSessionId = UUID()
    do {
      _ = try await strictSessionService.setItemChecked(
        sessionId: nonexistentSessionId,
        itemId: item.id,
        isChecked: true
      )
      XCTFail("Expected sessionNotFound error")
    } catch {
      XCTAssertEqual(error, .sessionNotFound(nonexistentSessionId))
    }

    // 2. Immediate valid retry within the 10s window must NOT be debounced
    let updated = try await strictSessionService.setItemChecked(
      sessionId: session.id,
      itemId: item.id,
      isChecked: true
    )
    XCTAssertTrue(try XCTUnwrap(updated.items.first).isChecked)
  }
}
