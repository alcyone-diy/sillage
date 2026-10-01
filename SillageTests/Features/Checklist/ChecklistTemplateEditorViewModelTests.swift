//
//  ChecklistTemplateEditorViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class ChecklistTemplateEditorViewModelTests: XCTestCase {
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

  // MARK: - Creation Mode Tests

  func testCreationInitialState() {
    let viewModel = ChecklistTemplateEditorViewModel(
      checklistService: checklistService,
      initialCategory: .routine
    )

    XCTAssertNil(viewModel.templateId)
    XCTAssertFalse(viewModel.isEditing)
    XCTAssertEqual(viewModel.title, "")
    XCTAssertEqual(viewModel.descriptionText, "")
    XCTAssertEqual(viewModel.category, .routine)
    XCTAssertEqual(viewModel.items.count, 1)
    XCTAssertEqual(viewModel.items.first?.title, "")
    XCTAssertFalse(viewModel.isValid)
    XCTAssertFalse(viewModel.isSaving)
    XCTAssertNil(viewModel.errorMessage)
  }

  func testValidationRequiresTitleAndNonEmptyItem() {
    let viewModel = ChecklistTemplateEditorViewModel(checklistService: checklistService)

    // 1. Both empty -> invalid
    XCTAssertFalse(viewModel.isValid)

    // 2. Only title -> invalid (no valid item)
    viewModel.title = "Night Watch"
    XCTAssertFalse(viewModel.isValid)

    // 3. Title with whitespace only -> invalid
    viewModel.title = "   "
    viewModel.items[0].title = "Log baro pressure"
    XCTAssertFalse(viewModel.isValid)

    // 4. Valid title and valid item -> valid
    viewModel.title = "Night Watch"
    viewModel.items[0].title = "Log baro pressure"
    XCTAssertTrue(viewModel.isValid)

    // 5. Additional blank item does not invalidate if at least one valid item exists
    viewModel.addItem(title: "")
    XCTAssertTrue(viewModel.isValid)
  }

  func testAddRemoveAndMoveItems() {
    let viewModel = ChecklistTemplateEditorViewModel(checklistService: checklistService)
    viewModel.items[0].title = "Step 1"
    viewModel.addItem(title: "Step 2", detail: "Step 2 detail")
    viewModel.addItem(title: "Step 3")
    XCTAssertEqual(viewModel.items.count, 3)

    // Move Step 1 to the end
    viewModel.moveItems(fromOffsets: IndexSet(integer: 0), toOffset: 3)
    XCTAssertEqual(viewModel.items[0].title, "Step 2")
    XCTAssertEqual(viewModel.items[1].title, "Step 3")
    XCTAssertEqual(viewModel.items[2].title, "Step 1")

    // Remove middle item
    viewModel.removeItems(atOffsets: IndexSet(integer: 1))
    XCTAssertEqual(viewModel.items.count, 2)
    XCTAssertEqual(viewModel.items[0].title, "Step 2")
    XCTAssertEqual(viewModel.items[1].title, "Step 1")
  }

  func testMoveItemUpAndDown() {
    let viewModel = ChecklistTemplateEditorViewModel(checklistService: checklistService)
    viewModel.items[0].title = "A"
    viewModel.addItem(title: "B")
    viewModel.addItem(title: "C")

    let bId = viewModel.items[1].id
    viewModel.moveItemUp(id: bId)
    XCTAssertEqual(viewModel.items.map(\.title), ["B", "A", "C"])

    viewModel.moveItemDown(id: bId)
    XCTAssertEqual(viewModel.items.map(\.title), ["A", "B", "C"])
  }

  func testSaveNewTemplate() async {
    let viewModel = ChecklistTemplateEditorViewModel(checklistService: checklistService)
    viewModel.title = "Passage Prep"
    viewModel.descriptionText = "Pre-passage safety checklist"
    viewModel.category = .safetyEmergency
    viewModel.items[0].title = "Check rigging"
    viewModel.items[0].detail = "Shrouds and stays tension"
    viewModel.addItem(title: "Verify fuel reserves")

    let saved = await viewModel.save()
    XCTAssertNotNil(saved)
    XCTAssertEqual(saved?.title, "Passage Prep")
    XCTAssertEqual(saved?.description, "Pre-passage safety checklist")
    XCTAssertEqual(saved?.category, .safetyEmergency)
    XCTAssertEqual(saved?.items.count, 2)
    XCTAssertFalse(viewModel.isSaving)
  }

  // MARK: - Edit Mode Tests

  func testEditExistingTemplate() async throws {
    let existing = try await checklistService.createCustomTemplate(
      title: "Original Title",
      description: "Original description",
      category: .routine,
      items: [
        (title: "Original Step 1", detail: "Detail 1"),
        (title: "Original Step 2", detail: "Detail 2")
      ]
    )

    let viewModel = ChecklistTemplateEditorViewModel(
      template: existing,
      checklistService: checklistService
    )

    XCTAssertTrue(viewModel.isEditing)
    XCTAssertEqual(viewModel.templateId, existing.id)
    XCTAssertEqual(viewModel.title, "Original Title")
    XCTAssertEqual(viewModel.items.count, 2)

    viewModel.title = "Updated Title"
    viewModel.items[0].title = "Modified Step 1"
    viewModel.addItem(title: "New Step 3")

    let updated = await viewModel.save()
    XCTAssertNotNil(updated)
    XCTAssertEqual(updated?.id, existing.id)
    XCTAssertEqual(updated?.title, "Updated Title")
    XCTAssertEqual(updated?.items.count, 3)

    let reloaded = try await checklistService.fetchTemplate(id: existing.id)
    XCTAssertEqual(reloaded?.title, "Updated Title")
    XCTAssertEqual(reloaded?.items.count, 3)
  }
}
