//
//  ChecklistEditViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-28.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class ChecklistEditViewModelTests: XCTestCase {
  private var databaseManager: DatabaseManager!
  private var checklistService: ChecklistService!
  private var initialTemplate: ChecklistTemplate!
  private var viewModel: ChecklistEditViewModel!

  override func setUp() async throws {
    try await super.setUp()
    databaseManager = try DatabaseManager.inMemory()
    checklistService = ChecklistService(
      databaseManager: databaseManager,
      throttler: ChecklistThrottler(window: .zero)
    )

    initialTemplate = try await checklistService.createCustomTemplate(
      title: "Initial Checklist",
      description: "Initial description",
      category: .routine,
      items: [
        ("Step 1", "Detail 1"),
        ("Step 2", "Detail 2")
      ]
    )

    viewModel = ChecklistEditViewModel(
      template: initialTemplate,
      checklistService: checklistService
    )
  }

  override func tearDown() async throws {
    viewModel = nil
    initialTemplate = nil
    checklistService = nil
    databaseManager = nil
    try await super.tearDown()
  }

  // MARK: - Initial State Tests

  func testInitialState() {
    XCTAssertEqual(viewModel.templateId, initialTemplate.id)
    XCTAssertEqual(viewModel.title, "Initial Checklist")
    XCTAssertEqual(viewModel.descriptionText, "Initial description")
    XCTAssertEqual(viewModel.category, .routine)
    XCTAssertEqual(viewModel.items.count, 2)
    XCTAssertEqual(viewModel.items[0].title, "Step 1")
    XCTAssertEqual(viewModel.items[0].detail, "Detail 1")
    XCTAssertEqual(viewModel.items[1].title, "Step 2")
    XCTAssertTrue(viewModel.isValid)
    XCTAssertFalse(viewModel.isSaving)
    XCTAssertNil(viewModel.errorMessage)
  }

  // MARK: - Validation Tests

  func testValidationRequiresTitleAndNonEmptyItem() {
    // 1. Initial state is valid
    XCTAssertTrue(viewModel.isValid)

    // 2. Clear title -> invalid
    viewModel.title = ""
    XCTAssertFalse(viewModel.isValid)

    // 3. Title with whitespace only -> invalid
    viewModel.title = "   \n  "
    XCTAssertFalse(viewModel.isValid)

    // 4. Restore title, remove all items -> invalid
    viewModel.title = "Valid Title"
    viewModel.items.removeAll()
    XCTAssertFalse(viewModel.isValid)

    // 5. Items with only empty titles -> invalid
    viewModel.items = [
      ChecklistItemDraft(title: "", detail: "Has detail but no title"),
      ChecklistItemDraft(title: "   ", detail: "")
    ]
    XCTAssertFalse(viewModel.isValid)

    // 6. At least one non-empty item title -> valid
    viewModel.addItem(title: "Valid Step", detail: "")
    XCTAssertTrue(viewModel.isValid)
  }

  func testValidationErrorMessageExplanations() {
    // Both title and items empty
    viewModel.title = "   "
    viewModel.items = [ChecklistItemDraft(title: "  ")]
    XCTAssertEqual(
      viewModel.validationErrorMessage,
      String(localized: "Please provide a title and at least one step for your checklist.")
    )

    // Title empty, items non-empty
    viewModel.title = ""
    viewModel.items = [ChecklistItemDraft(title: "Valid Step")]
    XCTAssertEqual(
      viewModel.validationErrorMessage,
      String(localized: "Please provide a title for your checklist.")
    )

    // Title present, items empty
    viewModel.title = "Valid Title"
    viewModel.items = [ChecklistItemDraft(title: "  ")]
    XCTAssertEqual(
      viewModel.validationErrorMessage,
      String(localized: "Please add at least one step with a title to your checklist.")
    )

    // Both valid -> nil
    viewModel.items = [ChecklistItemDraft(title: "Valid Step")]
    XCTAssertNil(viewModel.validationErrorMessage)
  }

  // MARK: - Item Management Tests

  func testAddRemoveAndMoveItems() {
    // Initial has 2 items
    XCTAssertEqual(viewModel.items.count, 2)

    // Add item
    viewModel.addItem(title: "Step 3", detail: "Detail 3")
    XCTAssertEqual(viewModel.items.count, 3)
    XCTAssertEqual(viewModel.items.last?.title, "Step 3")

    // Remove first item
    viewModel.removeItems(atOffsets: IndexSet(integer: 0))
    XCTAssertEqual(viewModel.items.count, 2)
    XCTAssertEqual(viewModel.items.first?.title, "Step 2")

    // Move item
    viewModel.moveItems(fromOffsets: IndexSet(integer: 1), toOffset: 0)
    XCTAssertEqual(viewModel.items.first?.title, "Step 3")
    XCTAssertEqual(viewModel.items.last?.title, "Step 2")
  }

  func testMoveItemUpAndDownByIndex() {
    viewModel.addItem(title: "Step 3")

    // Move index 2 up
    viewModel.moveItemUp(at: 2)
    XCTAssertEqual(viewModel.items[1].title, "Step 3")
    XCTAssertEqual(viewModel.items[2].title, "Step 2")

    // Move index 0 up (no-op)
    viewModel.moveItemUp(at: 0)
    XCTAssertEqual(viewModel.items[0].title, "Step 1")

    // Move index 1 down
    viewModel.moveItemDown(at: 1)
    XCTAssertEqual(viewModel.items[1].title, "Step 2")
    XCTAssertEqual(viewModel.items[2].title, "Step 3")

    // Move index 2 down (no-op)
    viewModel.moveItemDown(at: 2)
    XCTAssertEqual(viewModel.items[2].title, "Step 3")
  }

  func testMoveItemUpAndDownById() {
    viewModel.addItem(title: "Step 3")
    guard let step3Id = viewModel.items.last?.id else {
      XCTFail("Missing step 3 id")
      return
    }

    viewModel.moveItemUp(id: step3Id)
    XCTAssertEqual(viewModel.items[1].id, step3Id)

    viewModel.moveItemDown(id: step3Id)
    XCTAssertEqual(viewModel.items[2].id, step3Id)
  }

  // MARK: - Save Persistence Tests

  func testSaveSuccessPersistsUpdatedTemplate() async throws {
    viewModel.title = "Refactored Checklist"
    viewModel.descriptionText = "Updated notes"
    viewModel.category = .engineTechnical
    viewModel.items = [
      ChecklistItemDraft(title: "Check cooling liquid", detail: "Level max"),
      ChecklistItemDraft(title: "Inspect impeller", detail: "")
    ]

    let updated = await viewModel.save()
    XCTAssertNotNil(updated)
    XCTAssertEqual(updated?.id, initialTemplate.id)
    XCTAssertEqual(updated?.title, "Refactored Checklist")
    XCTAssertEqual(updated?.description, "Updated notes")
    XCTAssertEqual(updated?.category, .engineTechnical)
    XCTAssertEqual(updated?.items.count, 2)
    XCTAssertEqual(updated?.items[0].title, "Check cooling liquid")
    XCTAssertEqual(updated?.items[1].title, "Inspect impeller")
    XCTAssertFalse(viewModel.isSaving)
    XCTAssertNil(viewModel.errorMessage)

    // Confirm in DB
    let fetched = try await checklistService.fetchTemplate(id: initialTemplate.id)
    XCTAssertEqual(fetched?.title, "Refactored Checklist")
    XCTAssertEqual(fetched?.category, .engineTechnical)
  }

  func testSaveFailsWhenInvalidSetsErrorAndAlertTitle() async {
    viewModel.title = ""
    let result = await viewModel.save()
    XCTAssertNil(result)
    XCTAssertEqual(viewModel.alertTitle, String(localized: "Incomplete Checklist"))
    XCTAssertEqual(viewModel.errorMessage, String(localized: "Please provide a title for your checklist."))
  }
}
