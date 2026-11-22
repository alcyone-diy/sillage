//
//  ChecklistTemplateListViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-30.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import GRDB
@testable import Sillage

@MainActor
final class ChecklistTemplateListViewModelTests: XCTestCase {
  private var databaseManager: DatabaseManager?
  private var checklistService: ChecklistService?
  private var viewModel: ChecklistTemplateListViewModel?

  override func setUp() async throws {
    try await super.setUp()
    let dbManager = try DatabaseManager.inMemory()
    let service = ChecklistService(
      databaseManager: dbManager,
      throttler: ChecklistThrottler(window: .zero)
    )
    self.databaseManager = dbManager
    self.checklistService = service
    self.viewModel = ChecklistTemplateListViewModel(checklistService: service)
  }

  override func tearDown() async throws {
    viewModel = nil
    checklistService = nil
    databaseManager = nil
    try await super.tearDown()
  }

  // MARK: - Initial State Tests

  func testInitialState() throws {
    let vm = try XCTUnwrap(viewModel)
    XCTAssertTrue(vm.templates.isEmpty)
    XCTAssertTrue(vm.activeSessions.isEmpty)
    XCTAssertFalse(vm.isLoading)
    XCTAssertNil(vm.errorMessage)
    XCTAssertTrue(vm.groupedByCategoryItem.isEmpty)
  }

  // MARK: - Loading Templates Tests

  func testLoadTemplates() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    _ = try await service.createCustomTemplate(
      title: "Routine Check",
      description: "Routine items",
      categoryId: "routine",
      items: [("Item 1", "Detail 1")]
    )
    _ = try await service.createCustomTemplate(
      title: "Safety Brief",
      description: "Emergency equipment",
      categoryId: "safety_emergency",
      items: [("Lifejackets", "On deck")]
    )

    await vm.loadTemplates()

    XCTAssertEqual(vm.templates.count, 2)
    XCTAssertEqual(vm.groupedByCategoryItem.count, 2)
    XCTAssertNil(vm.errorMessage)
  }

  func testTemplatesSortedAlphabeticallyWhenSameSortOrder() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    // createCustomTemplate assigns sort_order = 0 to each custom template,
    // so this tests the alphabetical fallback when sortOrder is identical.
    _ = try await service.createCustomTemplate(
      title: "Zebra Checklist",
      description: nil,
      categoryId: "routine",
      items: [("Z1", nil)]
    )
    _ = try await service.createCustomTemplate(
      title: "Alpha Checklist",
      description: nil,
      categoryId: "routine",
      items: [("A1", nil)]
    )
    _ = try await service.createCustomTemplate(
      title: "Beta Checklist",
      description: nil,
      categoryId: "routine",
      items: [("B1", nil)]
    )

    await vm.loadTemplates()

    XCTAssertEqual(vm.templates.map(\.title), ["Alpha Checklist", "Beta Checklist", "Zebra Checklist"])

    let routineSection = try XCTUnwrap(vm.groupedByCategoryItem.first(where: { $0.category.id == "routine" }))
    XCTAssertEqual(routineSection.templates.map(\.title), ["Alpha Checklist", "Beta Checklist", "Zebra Checklist"])
  }

  func testTemplatesSortedByManualSortOrderOverridesAlphabetical() async throws {
    let dbManager = try XCTUnwrap(databaseManager)
    let vm = try XCTUnwrap(viewModel)

    // Insert templates directly with explicit, distinct sort_order values
    try await dbManager.write { db in
      try ChecklistTemplateRecord(
        id: UUID().uuidString,
        title: "Zulu Checklist",
        description: nil,
        category_id: "routine",
        sort_order: 1,
        created_at: Date(),
        updated_at: Date()
      ).insert(db)

      try ChecklistTemplateRecord(
        id: UUID().uuidString,
        title: "Alpha Checklist",
        description: nil,
        category_id: "routine",
        sort_order: 2,
        created_at: Date(),
        updated_at: Date()
      ).insert(db)
    }

    await vm.loadTemplates()

    // sort_order 1 ("Zulu Checklist") MUST precede sort_order 2 ("Alpha Checklist")
    XCTAssertEqual(vm.templates.map(\.title), ["Zulu Checklist", "Alpha Checklist"])

    let routineSection = try XCTUnwrap(vm.groupedByCategoryItem.first(where: { $0.category.id == "routine" }))
    XCTAssertEqual(routineSection.templates.map(\.title), ["Zulu Checklist", "Alpha Checklist"])
  }

  func testStandardComparatorUnitLogic() {
    let zuluOrder1 = ChecklistTemplate(
      id: UUID(),
      title: "Zulu",
      categoryId: "routine",
      sortOrder: 1
    )
    let alphaOrder2 = ChecklistTemplate(
      id: UUID(),
      title: "Alpha",
      categoryId: "routine",
      sortOrder: 2
    )
    let betaOrder2 = ChecklistTemplate(
      id: UUID(),
      title: "Beta",
      categoryId: "routine",
      sortOrder: 2
    )

    // Primary: sortOrder takes precedence over alphabetical
    XCTAssertTrue(ChecklistTemplate.standardComparator(zuluOrder1, alphaOrder2))
    XCTAssertFalse(ChecklistTemplate.standardComparator(alphaOrder2, zuluOrder1))

    // Fallback: alphabetical takes precedence when sortOrder is identical
    XCTAssertTrue(ChecklistTemplate.standardComparator(alphaOrder2, betaOrder2))
    XCTAssertFalse(ChecklistTemplate.standardComparator(betaOrder2, alphaOrder2))
  }

  // MARK: - Active Sessions Observation Tests

  func testActiveSessionsTracking() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    let template = try await service.createCustomTemplate(
      title: "Navigation Prep",
      description: nil,
      categoryId: "navigation_maneuver",
      items: [("Check charts", nil)]
    )

    XCTAssertFalse(vm.hasActiveSession(for: template.id))
    XCTAssertNil(vm.activeSession(for: template.id))

    // Start session (0 items completed initially)
    let session = try await service.startSession(templateId: template.id)

    let observeTask = Task { [weak viewModel] in
      await viewModel?.observeActiveSessions()
    }

    try await Task.sleep(nanoseconds: 50_000_000)

    // With 0 items completed, it should not be considered "in progress" to continue (action is "Start")
    XCTAssertFalse(vm.hasActiveSession(for: template.id))
    XCTAssertNil(vm.activeSession(for: template.id))

    // Check an item
    guard let firstItem = session.items.first else {
      XCTFail("Expected template item in session")
      observeTask.cancel()
      return
    }

    _ = try await service.setItemChecked(
      sessionId: session.id,
      itemId: firstItem.id,
      isChecked: true,
      coordinate: nil
    )

    try await Task.sleep(nanoseconds: 50_000_000)

    // With progress (> 0 completed), it is active to continue
    XCTAssertTrue(vm.hasActiveSession(for: template.id))
    XCTAssertEqual(vm.activeSession(for: template.id)?.id, session.id)

    // Delete session
    try await service.deleteSession(sessionId: session.id)

    try await Task.sleep(nanoseconds: 50_000_000)

    // After deletion, session is removed, so it returns to "Start"
    XCTAssertFalse(vm.hasActiveSession(for: template.id))
    XCTAssertNil(vm.activeSession(for: template.id))

    observeTask.cancel()
  }

  // MARK: - Start or Resume Session Tests

  func testStartOrResumeSessionReturnsSessionId() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    let template = try await service.createCustomTemplate(
      title: "Quick Check",
      description: nil,
      categoryId: "routine",
      items: [("Step 1", nil)]
    )

    let session = await vm.startOrResumeSession(for: template.id)
    XCTAssertNotNil(session)

    // Resuming returns the same active session ID
    let resumedSession = await vm.startOrResumeSession(for: template.id)
    XCTAssertEqual(session?.id, resumedSession?.id)
  }

  // MARK: - Completed Sessions Observation Tests

  func testCompletedSessionsTracking() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    let template = try await service.createCustomTemplate(
      title: "Departure Checklist",
      description: nil,
      categoryId: "routine",
      items: [("Check bilge", nil), ("Stow gear", nil)]
    )

    XCTAssertNil(vm.latestCompletionDate(for: template.id))

    let observeTask = Task { [weak viewModel] in
      await viewModel?.observeCompletedSessions()
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertNil(vm.latestCompletionDate(for: template.id))

    // Start session and complete all items
    let session = try await service.startSession(templateId: template.id)
    for item in session.items {
      _ = try await service.setItemChecked(
        sessionId: session.id,
        itemId: item.id,
        isChecked: true,
        coordinate: nil
      )
    }

    // Complete the session
    let completed = try await service.completeSession(sessionId: session.id, notes: nil)
    try await Task.sleep(nanoseconds: 50_000_000)

    let latestDate = vm.latestCompletionDate(for: template.id)
    XCTAssertNotNil(latestDate)
    if let latestDate, let completedAt = completed.completedAt {
      XCTAssertEqual(latestDate.timeIntervalSince1970, completedAt.timeIntervalSince1970, accuracy: 0.01)
    }
    XCTAssertFalse(vm.hasActiveSession(for: template.id))

    observeTask.cancel()
  }

  // MARK: - Category Management Tests

  func testCategoriesLoadedAndGroupedByCategoryItem() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    let customCategory = try await service.createCategory(
      id: "custom_moorings",
      name: "Moorings & Anchoring",
      icon: "anchor",
      sortOrder: 10
    )

    _ = try await service.createCustomTemplate(
      title: "Anchorage Check",
      description: "Depth and swing radius",
      categoryId: customCategory.id,
      items: [("Set anchor", nil)]
    )

    await vm.loadTemplates()

    XCTAssertFalse(vm.categories.isEmpty)
    XCTAssertTrue(vm.categories.contains(where: { $0.id == "custom_moorings" }))

    let customGroup = vm.groupedByCategoryItem.first(where: { $0.category.id == "custom_moorings" })
    XCTAssertNotNil(customGroup)
    XCTAssertEqual(customGroup?.templates.count, 1)
    XCTAssertEqual(customGroup?.templates.first?.title, "Anchorage Check")
  }

  func testCreateAndDeleteCategoryViaViewModel() async throws {
    let vm = try XCTUnwrap(viewModel)

    await vm.loadCategories()
    let initialCount = vm.categories.count

    let created = await vm.createCategory(
      name: "Diving Operations",
      icon: "figure.open.water.swim",
      sortOrder: 20
    )
    let createdCategory = try XCTUnwrap(created)
    XCTAssertEqual(createdCategory.name, "Diving Operations")
    XCTAssertEqual(vm.categories.count, initialCount + 1)
    XCTAssertEqual(vm.category(for: createdCategory.id)?.name, "Diving Operations")

    let deleted = await vm.deleteCategory(id: createdCategory.id)
    XCTAssertTrue(deleted)
    XCTAssertEqual(vm.categories.count, initialCount)
    XCTAssertNil(vm.category(for: createdCategory.id))
  }
}
