//
//  ChecklistCreateViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class ChecklistCreateViewModelTests: XCTestCase {
  private var databaseManager: DatabaseManager!
  private var checklistService: ChecklistService!
  private var viewModel: ChecklistCreateViewModel!

  override func setUp() async throws {
    try await super.setUp()
    databaseManager = try DatabaseManager.inMemory()
    checklistService = ChecklistService(
      databaseManager: databaseManager,
      throttler: ChecklistThrottler(window: .zero)
    )
    viewModel = ChecklistCreateViewModel(checklistService: checklistService)
  }

  override func tearDown() async throws {
    viewModel = nil
    checklistService = nil
    databaseManager = nil
    try await super.tearDown()
  }

  // MARK: - Initial State Tests

  func testInitialState() {
    XCTAssertEqual(viewModel.title, "")
    XCTAssertEqual(viewModel.descriptionText, "")
    XCTAssertEqual(viewModel.category, .routine)
    XCTAssertEqual(viewModel.items.count, 1)
    XCTAssertEqual(viewModel.items.first?.title, "")
    XCTAssertFalse(viewModel.isValid)
    XCTAssertFalse(viewModel.isSaving)
    XCTAssertNil(viewModel.errorMessage)
  }

  // MARK: - Validation Tests

  func testValidationRequiresTitleAndNonEmptyItem() {
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

  // MARK: - Item Mutation Tests

  func testAddRemoveAndMoveItems() {
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

  func testMoveItemUpAndDownByIndex() {
    viewModel.items[0].title = "A"
    viewModel.addItem(title: "B")
    viewModel.addItem(title: "C")

    // Move middle item up
    viewModel.moveItemUp(at: 1)
    XCTAssertEqual(viewModel.items.map(\.title), ["B", "A", "C"])

    // Move first item up (noop)
    viewModel.moveItemUp(at: 0)
    XCTAssertEqual(viewModel.items.map(\.title), ["B", "A", "C"])

    // Move middle item down
    viewModel.moveItemDown(at: 1)
    XCTAssertEqual(viewModel.items.map(\.title), ["B", "C", "A"])

    // Move last item down (noop)
    viewModel.moveItemDown(at: 2)
    XCTAssertEqual(viewModel.items.map(\.title), ["B", "C", "A"])

    // Out of bounds guards
    viewModel.moveItemUp(at: -1)
    viewModel.moveItemDown(at: 10)
    XCTAssertEqual(viewModel.items.map(\.title), ["B", "C", "A"])
  }

  func testMoveItemUpAndDownById() {
    viewModel.items[0].title = "First"
    viewModel.addItem(title: "Second")
    let secondId = viewModel.items[1].id

    // Move second item up by ID
    viewModel.moveItemUp(id: secondId)
    XCTAssertEqual(viewModel.items.map(\.title), ["Second", "First"])

    // Move it down again by ID
    viewModel.moveItemDown(id: secondId)
    XCTAssertEqual(viewModel.items.map(\.title), ["First", "Second"])

    // Nonexistent ID (noop)
    viewModel.moveItemUp(id: UUID())
    viewModel.moveItemDown(id: UUID())
    XCTAssertEqual(viewModel.items.map(\.title), ["First", "Second"])
  }

  // MARK: - Validation & Save Tests

  func testValidationErrorMessageExplanations() {
    // 1. Both title and steps empty
    viewModel.title = "   "
    viewModel.items[0].title = ""
    XCTAssertFalse(viewModel.isValid)
    XCTAssertEqual(
      viewModel.validationErrorMessage,
      String(localized: "Please provide a title and at least one step for your checklist.")
    )

    // 2. Title empty, but step provided
    viewModel.items[0].title = "Check seacocks"
    XCTAssertFalse(viewModel.isValid)
    XCTAssertEqual(
      viewModel.validationErrorMessage,
      String(localized: "Please provide a title for your checklist.")
    )

    // 3. Title provided, but steps empty
    viewModel.title = "Departure Prep"
    viewModel.items[0].title = "   "
    XCTAssertFalse(viewModel.isValid)
    XCTAssertEqual(
      viewModel.validationErrorMessage,
      String(localized: "Please add at least one step with a title to your checklist.")
    )

    // 4. Valid title and step
    viewModel.items[0].title = "Check seacocks"
    XCTAssertTrue(viewModel.isValid)
    XCTAssertNil(viewModel.validationErrorMessage)
  }

  func testSaveFailsWhenInvalidSetsErrorAndAlertTitle() async {
    viewModel.title = ""
    viewModel.items[0].title = ""

    let result = await viewModel.save()
    XCTAssertNil(result)
    XCTAssertEqual(viewModel.alertTitle, String(localized: "Incomplete Checklist"))
    XCTAssertEqual(
      viewModel.errorMessage,
      String(localized: "Please provide a title and at least one step for your checklist.")
    )
  }

  func testSaveSuccessPersistsTemplateAndItems() async throws {
    viewModel.title = "Engine Check"
    viewModel.descriptionText = "Pre-start inspection"
    viewModel.category = .engineTechnical
    viewModel.items[0].title = "Check oil level"
    viewModel.items[0].detail = "Must be between MIN and MAX marks"

    viewModel.addItem(title: "Check coolant", detail: "Visual inspection")
    // Add a trailing empty item that should be safely filtered out
    viewModel.addItem(title: "   ")

    XCTAssertTrue(viewModel.isValid)

    let createdTemplate = await viewModel.save()
    XCTAssertNotNil(createdTemplate)
    guard let template = createdTemplate else { return }

    XCTAssertEqual(template.title, "Engine Check")
    XCTAssertEqual(template.description, "Pre-start inspection")
    XCTAssertEqual(template.category, .engineTechnical)
    XCTAssertFalse(template.isSystem)
    XCTAssertEqual(template.items.count, 2)
    XCTAssertEqual(template.items[0].title, "Check oil level")
    XCTAssertEqual(template.items[0].detail, "Must be between MIN and MAX marks")
    XCTAssertEqual(template.items[1].title, "Check coolant")

    // Verify persisted in database
    let allTemplates = try await checklistService.fetchTemplates()
    XCTAssertTrue(allTemplates.contains(where: { $0.id == template.id }))
  }
}
