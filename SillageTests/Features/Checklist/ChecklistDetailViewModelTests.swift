//
//  ChecklistDetailViewModelTests.swift
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
final class ChecklistDetailViewModelTests: XCTestCase {
  private var databaseManager: DatabaseManager!
  private var checklistService: ChecklistService!
  private var template: ChecklistTemplate!
  private var viewModel: ChecklistDetailViewModel!

  override func setUp() async throws {
    try await super.setUp()
    databaseManager = try DatabaseManager.inMemory()
    checklistService = ChecklistService(
      databaseManager: databaseManager,
      throttler: ChecklistThrottler(window: .zero)
    )

    template = try await checklistService.createCustomTemplate(
      title: "Engine Check",
      description: "Pre-departure engine inspection",
      category: .engineTechnical,
      items: [
        (title: "Check oil level", detail: "Dipstick between MIN and MAX", isMandatory: true),
        (title: "Check raw water strainer", detail: "Free of weed and debris", isMandatory: true),
        (title: "Visual belt check", detail: "Check tension and wear", isMandatory: false)
      ]
    )

    viewModel = ChecklistDetailViewModel(
      templateId: template.id,
      checklistService: checklistService
    )
  }

  override func tearDown() async throws {
    viewModel = nil
    template = nil
    checklistService = nil
    databaseManager = nil
    try await super.tearDown()
  }

  // MARK: - Load & Get-or-Create Tests

  func testLoadStartsExecutionAndLoadsTemplate() async {
    XCTAssertNil(viewModel.template)
    XCTAssertNil(viewModel.execution)

    await viewModel.load()

    XCTAssertNotNil(viewModel.template)
    XCTAssertNotNil(viewModel.execution)
    XCTAssertEqual(viewModel.title, "Engine Check")
    XCTAssertEqual(viewModel.description, "Pre-departure engine inspection")
    XCTAssertEqual(viewModel.category, .engineTechnical)
    XCTAssertEqual(viewModel.items.count, 3)
    XCTAssertEqual(viewModel.completedCount, 0)
    XCTAssertEqual(viewModel.totalCount, 3)
    XCTAssertEqual(viewModel.progressRatio, 0.0)
    XCTAssertFalse(viewModel.isCompleted)
    XCTAssertFalse(viewModel.canComplete)
    XCTAssertFalse(viewModel.canReset)
    XCTAssertTrue(viewModel.canDeleteTemplate)
  }

  // MARK: - Item Toggle Tests

  func testToggleItemUpdatesCheckedStateAndProgress() async {
    await viewModel.load()
    guard let firstItem = viewModel.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    XCTAssertFalse(firstItem.isChecked)

    await viewModel.toggleItem(firstItem)

    XCTAssertEqual(viewModel.completedCount, 1)
    XCTAssertEqual(viewModel.progressRatio, 1.0 / 3.0)
    XCTAssertTrue(viewModel.canReset)
    XCTAssertFalse(viewModel.canComplete) // Still 1 mandatory item remaining

    // Toggle again to uncheck
    guard let updatedFirstItem = viewModel.items.first else {
      XCTFail("Items should not be empty")
      return
    }
    XCTAssertTrue(updatedFirstItem.isChecked)

    await viewModel.toggleItem(updatedFirstItem)

    XCTAssertEqual(viewModel.completedCount, 0)
    XCTAssertEqual(viewModel.progressRatio, 0.0)
  }

  // MARK: - Reset Tests

  func testResetUnchecksAllItems() async {
    await viewModel.load()
    for item in viewModel.items {
      await viewModel.toggleItem(item)
    }
    XCTAssertEqual(viewModel.completedCount, 3)
    XCTAssertTrue(viewModel.canReset)

    await viewModel.reset()

    XCTAssertEqual(viewModel.completedCount, 0)
    XCTAssertFalse(viewModel.canReset)
    XCTAssertTrue(viewModel.items.allSatisfy { !$0.isChecked })
  }

  // MARK: - Completion Tests

  func testCompleteRequiresAllMandatoryItems() async {
    await viewModel.load()

    // Check only optional item (index 2)
    let optionalItem = viewModel.items[2]
    await viewModel.toggleItem(optionalItem)

    XCTAssertFalse(viewModel.canComplete)
    XCTAssertFalse(viewModel.isAllMandatorySatisfied)

    // Check first mandatory item (index 0)
    let firstMandatory = viewModel.items[0]
    await viewModel.toggleItem(firstMandatory)
    XCTAssertFalse(viewModel.canComplete)

    // Check second mandatory item (index 1)
    let secondMandatory = viewModel.items[1]
    await viewModel.toggleItem(secondMandatory)
    XCTAssertTrue(viewModel.canComplete)
    XCTAssertTrue(viewModel.isAllMandatorySatisfied)

    // Complete session
    await viewModel.complete()
    XCTAssertTrue(viewModel.isCompleted)
    XCTAssertFalse(viewModel.canComplete)
  }

  // MARK: - Restart Session Tests

  func testRestartSessionCreatesNewActiveSession() async {
    await viewModel.load()

    // Complete all items
    for item in viewModel.items {
      await viewModel.toggleItem(item)
    }
    await viewModel.complete()
    XCTAssertTrue(viewModel.isCompleted)

    let previousExecutionId = viewModel.execution?.id

    // Restart
    await viewModel.restartSession()

    XCTAssertFalse(viewModel.isCompleted)
    XCTAssertEqual(viewModel.completedCount, 0)
    XCTAssertNotEqual(viewModel.execution?.id, previousExecutionId)
  }
}
