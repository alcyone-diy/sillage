//
//  ChecklistServiceTests.swift
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
final class ChecklistServiceTests: XCTestCase {
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

  // MARK: - Migration & Seeding Tests

  func testDefaultSeeding() async throws {
    try await checklistService.seedDefaultTemplatesIfNeeded()

    let templates = try await checklistService.fetchTemplates()
    XCTAssertEqual(templates.count, 4)

    // Second call should be a no-op
    try await checklistService.seedDefaultTemplatesIfNeeded()
    let templatesAfterSecondSeed = try await checklistService.fetchTemplates()
    XCTAssertEqual(templatesAfterSecondSeed.count, 4)
  }

  // MARK: - Template Operations Tests

  func testCreateAndFetchCustomTemplate() async throws {
    let items = [
      ("Check fuel tank", "Minimum 50% capacity"),
      ("Stow fenders", Optional<String>.none)
    ]

    let created = try await checklistService.createCustomTemplate(
      title: "Night Sailing Prep",
      description: "Night passage checklist",
      category: .routine,
      items: items
    )

    XCTAssertEqual(created.title, "Night Sailing Prep")
    XCTAssertEqual(created.category, .routine)
    XCTAssertEqual(created.items.count, 2)
    XCTAssertEqual(created.items[0].title, "Check fuel tank")

    let fetched = try await checklistService.fetchTemplate(id: created.id)
    XCTAssertNotNil(fetched)
    XCTAssertEqual(fetched?.id, created.id)
    XCTAssertEqual(fetched?.items.count, 2)
  }

  func testDeleteCustomTemplateWithoutHistory() async throws {
    let template = try await checklistService.createCustomTemplate(
      title: "Temporary Checklist",
      description: nil,
      category: .engineTechnical,
      items: [("Check belt", nil)]
    )

    try await checklistService.deleteCustomTemplate(id: template.id)
    let fetched = try await checklistService.fetchTemplate(id: template.id)
    XCTAssertNil(fetched)
  }

  func testCanDeleteSystemTemplateWithoutHistory() async throws {
    try await checklistService.seedDefaultTemplatesIfNeeded()
    let templates = try await checklistService.fetchTemplates()
    guard let template = templates.first else {
      XCTFail("No template found")
      return
    }

    try await checklistService.deleteTemplate(id: template.id)
    let fetched = try await checklistService.fetchTemplate(id: template.id)
    XCTAssertNil(fetched)
  }

  func testCannotDeleteTemplateWithHistory() async throws {
    try await checklistService.seedDefaultTemplatesIfNeeded()
    let templates = try await checklistService.fetchTemplates()
    guard let template = templates.first else {
      XCTFail("No template found")
      return
    }

    // Start an execution to create history
    _ = try await checklistService.startExecution(templateId: template.id)

    do {
      try await checklistService.deleteTemplate(id: template.id)
      XCTFail("Expected error when deleting template with execution history")
    } catch ChecklistExecutionError.templateHasExistingExecutions {
      // Expected
    }
  }

  func testCanUpdateDefaultTemplate() async throws {
    try await checklistService.seedDefaultTemplatesIfNeeded()
    let templates = try await checklistService.fetchTemplates()
    guard let template = templates.first else {
      XCTFail("No template found")
      return
    }

    let updated = try await checklistService.updateTemplate(
      id: template.id,
      title: "Modified Checklist",
      description: "User customized",
      category: .routine,
      items: [(id: nil, title: "Custom Step 1", detail: "Custom Detail")]
    )

    XCTAssertEqual(updated.title, "Modified Checklist")
    XCTAssertEqual(updated.items.count, 1)

    let fetched = try await checklistService.fetchTemplate(id: template.id)
    XCTAssertEqual(fetched?.title, "Modified Checklist")
  }

  func testDeletedTemplatesDoNotReseedOnRestart() async throws {
    try await checklistService.seedDefaultTemplatesIfNeeded()
    let templates = try await checklistService.fetchTemplates()
    XCTAssertEqual(templates.count, 4)

    // Delete all templates
    for template in templates {
      try await checklistService.deleteTemplate(id: template.id)
    }
    let afterDelete = try await checklistService.fetchTemplates()
    XCTAssertEqual(afterDelete.count, 0)

    // Calling seedDefaultTemplatesIfNeeded again must not recreate deleted templates
    try await checklistService.seedDefaultTemplatesIfNeeded()
    let afterReseedAttempt = try await checklistService.fetchTemplates()
    XCTAssertEqual(afterReseedAttempt.count, 0)
  }

  func testUpdateTemplateNotFound() async throws {
    do {
      _ = try await checklistService.updateCustomTemplate(
        id: UUID(),
        title: "Ghost",
        description: nil,
        category: .routine,
        items: [("Ghost step", nil)]
      )
      XCTFail("Expected error when updating non-existent template")
    } catch ChecklistExecutionError.templateNotFound {
      // Expected
    }
  }

  func testUpdateCustomTemplateUpdatesActiveExecutionSnapshot() async throws {
    let template = try await checklistService.createCustomTemplate(
      title: "Pre-Sail",
      description: nil,
      category: .routine,
      items: [("Check rigging", nil)]
    )

    let execution = try await checklistService.startExecution(templateId: template.id)
    XCTAssertEqual(execution.templateTitleSnapshot, "Pre-Sail")

    _ = try await checklistService.updateCustomTemplate(
      id: template.id,
      title: "Pre-Sail Rigging Check",
      description: nil,
      category: .routine,
      items: [("Check rigging thoroughly", nil)]
    )

    let activeExecution = try await checklistService.fetchActiveExecution(for: template.id)
    XCTAssertNotNil(activeExecution)
    XCTAssertEqual(activeExecution?.templateTitleSnapshot, "Pre-Sail Rigging Check")
  }

  func testUpdateCustomTemplateReordersActiveExecutionItemsAndPreservesCheckedState() async throws {
    let template = try await checklistService.createCustomTemplate(
      title: "Pre-Sail",
      description: nil,
      category: .routine,
      items: [
        ("Check bilges", nil),
        ("Check engine oil", nil),
        ("Turn on VHF", nil)
      ]
    )

    let execution = try await checklistService.startExecution(templateId: template.id)
    XCTAssertEqual(execution.items.count, 3)
    XCTAssertEqual(execution.items[0].title, "Check bilges")
    XCTAssertEqual(execution.items[1].title, "Check engine oil")
    XCTAssertEqual(execution.items[2].title, "Turn on VHF")

    // Check the first item ("Check bilges")
    let firstItemId = execution.items[0].id
    _ = try await checklistService.setItemChecked(
      executionId: execution.id,
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

    _ = try await checklistService.updateTemplate(
      id: template.id,
      title: "Pre-Sail Reordered",
      description: nil,
      category: .routine,
      items: reorderedItems
    )

    let activeExecution = try await checklistService.fetchActiveExecution(for: template.id)
    XCTAssertNotNil(activeExecution)
    guard let activeExecution else { return }

    XCTAssertEqual(activeExecution.items.count, 3)
    XCTAssertEqual(activeExecution.items[0].title, "Turn on VHF")
    XCTAssertFalse(activeExecution.items[0].isChecked)
    XCTAssertEqual(activeExecution.items[0].sortOrder, 0)

    XCTAssertEqual(activeExecution.items[1].title, "Check bilges")
    XCTAssertTrue(activeExecution.items[1].isChecked)
    XCTAssertEqual(activeExecution.items[1].sortOrder, 1)

    XCTAssertEqual(activeExecution.items[2].title, "Check engine oil")
    XCTAssertFalse(activeExecution.items[2].isChecked)
    XCTAssertEqual(activeExecution.items[2].sortOrder, 2)
  }

  // MARK: - Execution Lifecycle & Get-or-Create Tests

  func testStartExecutionAndGetOrCreate() async throws {
    let template = try await checklistService.createCustomTemplate(
      title: "Engine Start",
      description: nil,
      category: .engineTechnical,
      items: [
        ("Open seacock", nil),
        ("Check oil", nil)
      ]
    )

    // 1. Initial start
    let execution1 = try await checklistService.startExecution(templateId: template.id)
    XCTAssertEqual(execution1.templateId, template.id)
    XCTAssertEqual(execution1.status, .inProgress)
    XCTAssertEqual(execution1.items.count, 2)
    XCTAssertEqual(execution1.completedCount, 0)
    XCTAssertEqual(execution1.progressRatio, 0.0)

    // 2. Second start on same template -> Transparent resume (Get-or-Create)
    let execution2 = try await checklistService.startExecution(templateId: template.id)
    XCTAssertEqual(execution1.id, execution2.id)
  }

  func testSetItemCheckedIdempotencyAndCoordinate() async throws {
    let template = try await checklistService.createCustomTemplate(
      title: "Anchor Procedure",
      description: nil,
      category: .navigationManeuver,
      items: [
        ("Drop anchor", "Record coordinates"),
        ("Set snubber", nil)
      ]
    )

    let execution = try await checklistService.startExecution(templateId: template.id)
    let itemToToggle = execution.items[0]

    let coordinate = CLLocationCoordinate2D(latitude: 46.159, longitude: -1.152)

    // Check item with coordinate
    let updated1 = try await checklistService.setItemChecked(
      executionId: execution.id,
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
    let updated2 = try await checklistService.setItemChecked(
      executionId: execution.id,
      itemId: itemToToggle.id,
      isChecked: true,
      coordinate: coordinate
    )
    XCTAssertEqual(updated1.items.first?.checkedAt, updated2.items.first?.checkedAt)

    // Uncheck item
    let updated3 = try await checklistService.setItemChecked(
      executionId: execution.id,
      itemId: itemToToggle.id,
      isChecked: false,
      coordinate: nil
    )
    let uncheckedItem = updated3.items.first { $0.id == itemToToggle.id }
    XCTAssertFalse(uncheckedItem?.isChecked == true)
    XCTAssertNil(uncheckedItem?.checkedAt)
    XCTAssertNil(uncheckedItem?.coordinate)
  }

  func testResetExecution() async throws {
    let template = try await checklistService.createCustomTemplate(
      title: "Reset Test",
      description: nil,
      category: .routine,
      items: [
        ("Step 1", nil),
        ("Step 2", nil)
      ]
    )

    let execution = try await checklistService.startExecution(templateId: template.id)
    _ = try await checklistService.setItemChecked(
      executionId: execution.id,
      itemId: execution.items[0].id,
      isChecked: true,
      coordinate: nil
    )

    let resetExecution = try await checklistService.resetExecution(executionId: execution.id)
    XCTAssertEqual(resetExecution.completedCount, 0)
    XCTAssertTrue(resetExecution.items.allSatisfy { !$0.isChecked && $0.checkedAt == nil })
  }

  func testCompleteExecution() async throws {
    let template = try await checklistService.createCustomTemplate(
      title: "Completion Test",
      description: nil,
      category: .safetyEmergency,
      items: [
        ("Step 1", nil),
        ("Step 2", nil)
      ]
    )

    let execution = try await checklistService.startExecution(templateId: template.id)

    _ = try await checklistService.setItemChecked(
      executionId: execution.id,
      itemId: execution.items[0].id,
      isChecked: true,
      coordinate: nil
    )

    let completed = try await checklistService.completeExecution(
      executionId: execution.id,
      notes: "Executed in 2 minutes"
    )
    XCTAssertEqual(completed.status, .completed)
    XCTAssertNotNil(completed.completedAt)
    XCTAssertEqual(completed.notes, "Executed in 2 minutes")

    // Attempting completion again should fail
    do {
      _ = try await checklistService.completeExecution(executionId: execution.id, notes: nil)
      XCTFail("Expected executionAlreadyFinished error")
    } catch ChecklistExecutionError.executionAlreadyFinished {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testAbandonExecution() async throws {
    let template = try await checklistService.createCustomTemplate(
      title: "Abandon Test",
      description: nil,
      category: .routine,
      items: [("Task 1", nil)]
    )

    let execution = try await checklistService.startExecution(templateId: template.id)
    let abandoned = try await checklistService.abandonExecution(executionId: execution.id)

    XCTAssertEqual(abandoned.status, .abandoned)
    XCTAssertNotNil(abandoned.completedAt)

    // Modifying an abandoned execution should fail
    do {
      _ = try await checklistService.setItemChecked(
        executionId: execution.id,
        itemId: execution.items[0].id,
        isChecked: true,
        coordinate: nil
      )
      XCTFail("Expected executionAlreadyFinished error")
    } catch ChecklistExecutionError.executionAlreadyFinished {
      // Expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testCannotDeleteTemplateWithExecutions() async throws {
    let template = try await checklistService.createCustomTemplate(
      title: "History Protected",
      description: nil,
      category: .routine,
      items: [("Item", nil)]
    )

    let execution = try await checklistService.startExecution(templateId: template.id)
    _ = try await checklistService.abandonExecution(executionId: execution.id)

    do {
      try await checklistService.deleteCustomTemplate(id: template.id)
      XCTFail("Expected templateHasExistingExecutions error")
    } catch ChecklistExecutionError.templateHasExistingExecutions(let id) {
      XCTAssertEqual(id, template.id)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testReactiveActiveExecutionsObservation() async throws {
    let template = try await checklistService.createCustomTemplate(
      title: "Observation Test",
      description: nil,
      category: .routine,
      items: [("Step", nil)]
    )

    let stream = checklistService.observeActiveExecutions()
    var iterator = stream.makeAsyncIterator()

    // 1. Initial emission: empty array
    let initial = try await iterator.next()
    XCTAssertEqual(initial?.count, 0)

    // 2. Start execution
    let execution = try await checklistService.startExecution(templateId: template.id)
    let afterStart = try await iterator.next()
    XCTAssertEqual(afterStart?.count, 1)
    XCTAssertEqual(afterStart?.first?.id, execution.id)

    // 3. Complete execution
    _ = try await checklistService.completeExecution(executionId: execution.id, notes: nil)
    let afterComplete = try await iterator.next()
    XCTAssertEqual(afterComplete?.count, 0)
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
}
