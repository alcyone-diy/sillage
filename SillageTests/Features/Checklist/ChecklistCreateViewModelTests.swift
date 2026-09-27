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
    viewModel.addItem(title: "Step 2", detail: "Step 2 detail", isMandatory: true)
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

  // MARK: - Save Tests

  func testSaveFailsWhenInvalid() async {
    let result = await viewModel.save()
    XCTAssertNil(result)
  }

  func testSaveSuccessPersistsTemplateAndItems() async throws {
    viewModel.title = "Engine Check"
    viewModel.descriptionText = "Pre-start inspection"
    viewModel.category = .engineTechnical
    viewModel.items[0].title = "Check oil level"
    viewModel.items[0].detail = "Must be between MIN and MAX marks"
    viewModel.items[0].isMandatory = true

    viewModel.addItem(title: "Check coolant", detail: "Visual inspection", isMandatory: false)
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
    XCTAssertTrue(template.items[0].isMandatory)
    XCTAssertEqual(template.items[1].title, "Check coolant")
    XCTAssertFalse(template.items[1].isMandatory)

    // Verify persisted in database
    let allTemplates = try await checklistService.fetchTemplates()
    XCTAssertTrue(allTemplates.contains(where: { $0.id == template.id }))
  }
}
