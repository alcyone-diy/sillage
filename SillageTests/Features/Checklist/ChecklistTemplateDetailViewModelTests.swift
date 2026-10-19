//
//  ChecklistTemplateDetailViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import GRDB
@testable import Sillage

@MainActor
final class ChecklistTemplateDetailViewModelTests: XCTestCase {
  private var databaseManager: DatabaseManager?
  private var checklistService: ChecklistService?
  private var template: ChecklistTemplate?
  private var viewModel: ChecklistTemplateDetailViewModel?
  private var isolatedDefaults: IsolatedUserDefaults?

  override func setUp() async throws {
    try await super.setUp()
    let isolated = IsolatedUserDefaults(prefix: "ChecklistTemplateDetailViewModelTests")
    self.isolatedDefaults = isolated
    let db = try DatabaseManager.inMemory()
    self.databaseManager = db
    let service = ChecklistService(
      databaseManager: db,
      throttler: ChecklistThrottler(window: .zero),
      userDefaults: isolated.defaults
    )
    self.checklistService = service

    let createdTemplate = try await service.createCustomTemplate(
      title: "Pre-Sail Brief",
      description: "Safety walkaround",
      categoryId: "safety_emergency",
      items: [
        (title: "Lifejackets", detail: "Count matches crew"),
        (title: "EPIRB check", detail: "Battery valid")
      ]
    )
    self.template = createdTemplate

    self.viewModel = ChecklistTemplateDetailViewModel(
      templateId: createdTemplate.id,
      checklistService: service
    )
  }

  override func tearDown() async throws {
    viewModel = nil
    template = nil
    checklistService = nil
    databaseManager = nil
    isolatedDefaults?.tearDown()
    isolatedDefaults = nil
    try await super.tearDown()
  }

  // MARK: - Consultation & Loading Tests

  func testInitialState() throws {
    let vm = try XCTUnwrap(viewModel)
    let tmpl = try XCTUnwrap(template)

    XCTAssertEqual(vm.templateId, tmpl.id)
    XCTAssertNil(vm.template)
    XCTAssertNil(vm.activeSession)
    XCTAssertNil(vm.latestCompletionDate)
    XCTAssertNil(vm.activeSessionWithProgress)
    XCTAssertEqual(vm.usageStatus, .neverUsed)
    XCTAssertFalse(vm.isLoading)
    XCTAssertNil(vm.errorMessage)
    XCTAssertEqual(vm.title, "")
    XCTAssertNil(vm.description)
    XCTAssertEqual(vm.categoryId, "")
    XCTAssertTrue(vm.items.isEmpty)
    XCTAssertFalse(vm.hasActiveSession)
    XCTAssertFalse(vm.isEditable)
    XCTAssertTrue(vm.isEditing)
    XCTAssertTrue(vm.canDelete)
  }

  func testLoadTemplate() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()

    XCTAssertNotNil(vm.template)
    XCTAssertEqual(vm.title, "Pre-Sail Brief")
    XCTAssertEqual(vm.description, "Safety walkaround")
    XCTAssertEqual(vm.categoryId, "safety_emergency")
    guard vm.items.count == 2 else {
      XCTFail("Expected 2 items after loading")
      return
    }
    XCTAssertEqual(vm.items[0].title, "Lifejackets")
    XCTAssertEqual(vm.items[1].title, "EPIRB check")
    XCTAssertFalse(vm.hasActiveSession)
    XCTAssertNil(vm.latestCompletionDate)
    XCTAssertEqual(vm.usageStatus, .neverUsed)
    XCTAssertEqual(vm.usageStatusDescription, "Never used")
  }

  func testUsageStatusWithActiveSessionAndProgress() async throws {
    let service = try XCTUnwrap(checklistService)
    let tmpl = try XCTUnwrap(template)
    let vm = try XCTUnwrap(viewModel)

    let session = try await service.startSession(templateId: tmpl.id)
    guard let firstItem = session.items.first else {
      XCTFail("Expected session to have items")
      return
    }
    _ = try await service.setItemChecked(
      sessionId: session.id,
      itemId: firstItem.id,
      isChecked: true,
      coordinate: nil
    )

    await vm.load()

    XCTAssertTrue(vm.hasActiveSession)
    XCTAssertNotNil(vm.activeSessionWithProgress)
    if case .inProgress(let currentSession) = vm.usageStatus {
      XCTAssertEqual(currentSession.id, session.id)
      XCTAssertEqual(currentSession.completedCount, 1)
    } else {
      XCTFail("Expected usageStatus to be .inProgress, got \(vm.usageStatus)")
    }
    XCTAssertTrue(vm.usageStatusDescription.contains("1/"))
  }

  func testUsageStatusWithCompletedSession() async throws {
    let service = try XCTUnwrap(checklistService)
    let tmpl = try XCTUnwrap(template)
    let vm = try XCTUnwrap(viewModel)

    let session = try await service.startSession(templateId: tmpl.id)
    for item in session.items {
      _ = try await service.setItemChecked(
        sessionId: session.id,
        itemId: item.id,
        isChecked: true,
        coordinate: nil
      )
    }
    _ = try await service.completeSession(sessionId: session.id, notes: nil)

    await vm.load()

    XCTAssertFalse(vm.hasActiveSession)
    XCTAssertNil(vm.activeSessionWithProgress)
    XCTAssertNotNil(vm.latestCompletionDate)
    if case .completed(let date) = vm.usageStatus {
      XCTAssertEqual(date, vm.latestCompletionDate)
    } else {
      XCTFail("Expected usageStatus to be .completed, got \(vm.usageStatus)")
    }
    XCTAssertTrue(vm.usageStatusDescription.contains("Completed"))
  }

  func testObservationUpdatesActiveAndCompletedSessions() async throws {
    let service = try XCTUnwrap(checklistService)
    let tmpl = try XCTUnwrap(template)
    let vm = try XCTUnwrap(viewModel)

    let observeTask = Task { [weak vm] in
      await vm?.startObserving()
    }

    try await Task.sleep(nanoseconds: 50_000_000)

    let session = try await service.startSession(templateId: tmpl.id)
    guard let firstItem = session.items.first else {
      XCTFail("Expected session to have items")
      return
    }
    _ = try await service.setItemChecked(
      sessionId: session.id,
      itemId: firstItem.id,
      isChecked: true,
      coordinate: nil
    )

    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertTrue(vm.hasActiveSession)
    XCTAssertNotNil(vm.activeSessionWithProgress)
    if case .inProgress(let currentSession) = vm.usageStatus {
      XCTAssertEqual(currentSession.id, session.id)
      XCTAssertEqual(currentSession.completedCount, 1)
    } else {
      XCTFail("Expected usageStatus to be .inProgress, got \(vm.usageStatus)")
    }

    // Complete session
    for item in session.items {
      _ = try await service.setItemChecked(
        sessionId: session.id,
        itemId: item.id,
        isChecked: true,
        coordinate: nil
      )
    }
    _ = try await service.completeSession(sessionId: session.id, notes: nil)

    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.hasActiveSession)
    XCTAssertNil(vm.activeSessionWithProgress)
    XCTAssertNotNil(vm.latestCompletionDate)
    if case .completed(let date) = vm.usageStatus {
      XCTAssertEqual(date, vm.latestCompletionDate)
    } else {
      XCTFail("Expected usageStatus to be .completed, got \(vm.usageStatus)")
    }

    observeTask.cancel()
  }

  func testStartOrResumeSessionCreatesAndReturnsSessionId() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()

    let sessionId = await vm.startOrResumeSession()
    XCTAssertNotNil(sessionId)
    XCTAssertNotNil(vm.activeSession)
    XCTAssertEqual(vm.activeSession?.id, sessionId)
  }

  func testDeleteTemplate() async throws {
    let vm = try XCTUnwrap(viewModel)
    let service = try XCTUnwrap(checklistService)
    let tmpl = try XCTUnwrap(template)

    await vm.load()

    let success = await vm.deleteTemplate()
    XCTAssertTrue(success)

    let reloaded = try? await service.fetchTemplate(id: tmpl.id)
    XCTAssertNil(reloaded)
  }

  // MARK: - Editing & Mutation Tests

  func testRevertRestoresOriginalValues() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()

    guard !vm.items.isEmpty else {
      XCTFail("Expected items to not be empty after loading template")
      return
    }

    vm.isEditable = true
    vm.title = "Modified Title"
    vm.items[0].title = "Modified Step"

    vm.revert()

    XCTAssertFalse(vm.isEditable)
    XCTAssertEqual(vm.title, "Pre-Sail Brief")
    guard !vm.items.isEmpty else {
      XCTFail("Expected items to not be empty after reverting")
      return
    }
    XCTAssertEqual(vm.items[0].title, "Lifejackets")
  }

  func testSaveUpdatesTemplateAndSwitchesEditMode() async throws {
    let vm = try XCTUnwrap(viewModel)
    let service = try XCTUnwrap(checklistService)
    let tmpl = try XCTUnwrap(template)

    await vm.load()

    guard !vm.items.isEmpty else {
      XCTFail("Expected items to not be empty after loading template")
      return
    }

    vm.isEditable = true
    vm.title = "Updated Title"
    vm.items[0].title = "Updated Step 1"
    vm.addItem(title: "New Step 3")

    let saved = await vm.save()
    XCTAssertNotNil(saved)
    XCTAssertFalse(vm.isEditable)
    XCTAssertEqual(vm.title, "Updated Title")
    XCTAssertEqual(vm.items.count, 3)

    let reloaded = try? await service.fetchTemplate(id: tmpl.id)
    XCTAssertEqual(reloaded?.title, "Updated Title")
  }

  // MARK: - Creation Mode Tests

  func testCreationInitialState() throws {
    let service = try XCTUnwrap(checklistService)
    let creationVM = ChecklistTemplateDetailViewModel(
      checklistService: service,
      initialCategoryId: "routine"
    )

    XCTAssertNil(creationVM.templateId)
    XCTAssertFalse(creationVM.isEditing)
    XCTAssertTrue(creationVM.isEditable)
    XCTAssertTrue(creationVM.isNew)
    XCTAssertEqual(creationVM.title, "")
    XCTAssertEqual(creationVM.descriptionText, "")
    XCTAssertEqual(creationVM.categoryId, "routine")
    XCTAssertEqual(creationVM.items.count, 1)
    XCTAssertEqual(creationVM.items.first?.title, "")
    XCTAssertFalse(creationVM.canDelete)
    XCTAssertFalse(creationVM.isValid)
    XCTAssertFalse(creationVM.isSaving)
    XCTAssertNil(creationVM.errorMessage)
  }

  func testValidationRequiresCategoryTitleAndNonEmptyItem() throws {
    let service = try XCTUnwrap(checklistService)
    let creationVM = ChecklistTemplateDetailViewModel(
      checklistService: service,
      initialCategoryId: "routine"
    )

    // 0. Empty categoryId -> invalid
    creationVM.categoryId = ""
    creationVM.title = "Night Watch"
    creationVM.items[0].title = "Log baro pressure"
    XCTAssertFalse(creationVM.isValid)

    creationVM.categoryId = "routine"
    creationVM.title = ""
    creationVM.items[0].title = ""

    // 1. Both empty -> invalid
    XCTAssertFalse(creationVM.isValid)

    // 2. Only title -> invalid (no valid item)
    creationVM.title = "Night Watch"
    XCTAssertFalse(creationVM.isValid)

    // 3. Title with whitespace only -> invalid
    creationVM.title = "   "
    guard !creationVM.items.isEmpty else {
      XCTFail("Expected items to not be empty")
      return
    }
    creationVM.items[0].title = "Log baro pressure"
    XCTAssertFalse(creationVM.isValid)

    // 4. Valid title and valid item -> valid
    creationVM.title = "Night Watch"
    creationVM.items[0].title = "Log baro pressure"
    XCTAssertTrue(creationVM.isValid)

    // 5. Additional blank item does not invalidate if at least one valid item exists
    creationVM.addItem(title: "")
    XCTAssertTrue(creationVM.isValid)
  }

  func testAddRemoveAndMoveItems() throws {
    let service = try XCTUnwrap(checklistService)
    let creationVM = ChecklistTemplateDetailViewModel(checklistService: service)
    guard !creationVM.items.isEmpty else {
      XCTFail("Expected items to not be empty")
      return
    }
    creationVM.items[0].title = "Step 1"
    let addedItem = creationVM.addItem(title: "Step 2", detail: "Step 2 detail")
    XCTAssertEqual(addedItem.title, "Step 2")
    XCTAssertEqual(addedItem.detail, "Step 2 detail")
    XCTAssertEqual(creationVM.items.last?.id, addedItem.id)
    creationVM.addItem(title: "Step 3")
    XCTAssertEqual(creationVM.items.count, 3)

    // Move Step 1 to the end
    creationVM.moveItems(fromOffsets: IndexSet(integer: 0), toOffset: 3)
    guard creationVM.items.count == 3 else {
      XCTFail("Expected 3 items after move")
      return
    }
    XCTAssertEqual(creationVM.items[0].title, "Step 2")
    XCTAssertEqual(creationVM.items[1].title, "Step 3")
    XCTAssertEqual(creationVM.items[2].title, "Step 1")

    // Remove middle item
    creationVM.removeItems(atOffsets: IndexSet(integer: 1))
    guard creationVM.items.count == 2 else {
      XCTFail("Expected 2 items after removal")
      return
    }
    XCTAssertEqual(creationVM.items[0].title, "Step 2")
    XCTAssertEqual(creationVM.items[1].title, "Step 1")
  }

  func testMoveItemUpAndDown() throws {
    let service = try XCTUnwrap(checklistService)
    let creationVM = ChecklistTemplateDetailViewModel(checklistService: service)
    guard !creationVM.items.isEmpty else {
      XCTFail("Expected items to not be empty")
      return
    }
    creationVM.items[0].title = "A"
    creationVM.addItem(title: "B")
    creationVM.addItem(title: "C")

    guard creationVM.items.count >= 2 else {
      XCTFail("Expected at least 2 items")
      return
    }
    let bId = creationVM.items[1].id
    creationVM.moveItemUp(id: bId)
    XCTAssertEqual(creationVM.items.map(\.title), ["B", "A", "C"])

    creationVM.moveItemDown(id: bId)
    XCTAssertEqual(creationVM.items.map(\.title), ["A", "B", "C"])
  }

  func testSaveNewTemplate() async throws {
    let service = try XCTUnwrap(checklistService)
    let creationVM = ChecklistTemplateDetailViewModel(checklistService: service)
    creationVM.title = "Passage Prep"
    creationVM.descriptionText = "Pre-passage safety checklist"
    creationVM.categoryId = "safety_emergency"
    guard !creationVM.items.isEmpty else {
      XCTFail("Expected items to not be empty")
      return
    }
    creationVM.items[0].title = "Check rigging"
    creationVM.items[0].detail = "Shrouds and stays tension"
    creationVM.addItem(title: "Verify fuel reserves")

    let saved = await creationVM.save()
    XCTAssertNotNil(saved)
    XCTAssertEqual(saved?.title, "Passage Prep")
    XCTAssertEqual(saved?.description, "Pre-passage safety checklist")
    XCTAssertEqual(saved?.categoryId, "safety_emergency")
    XCTAssertEqual(saved?.items.count, 2)
    XCTAssertFalse(creationVM.isSaving)
    XCTAssertFalse(creationVM.isEditable)
    XCTAssertEqual(creationVM.templateId, saved?.id)
  }

  func testEditExistingTemplateViaDirectInit() async throws {
    let service = try XCTUnwrap(checklistService)
    let existing = try await service.createCustomTemplate(
      title: "Original Title",
      description: "Original description",
      categoryId: "routine",
      items: [
        (title: "Original Step 1", detail: "Detail 1"),
        (title: "Original Step 2", detail: "Detail 2")
      ]
    )

    let existingVM = ChecklistTemplateDetailViewModel(
      template: existing,
      checklistService: service,
      startEditable: true
    )

    XCTAssertTrue(existingVM.isEditing)
    XCTAssertTrue(existingVM.isEditable)
    XCTAssertEqual(existingVM.templateId, existing.id)
    XCTAssertEqual(existingVM.title, "Original Title")
    XCTAssertEqual(existingVM.items.count, 2)

    existingVM.title = "Updated Title"
    guard !existingVM.items.isEmpty else {
      XCTFail("Expected items to not be empty")
      return
    }
    existingVM.items[0].title = "Modified Step 1"
    existingVM.addItem(title: "New Step 3")

    let updated = await existingVM.save()
    XCTAssertNotNil(updated)
    XCTAssertEqual(updated?.id, existing.id)
    XCTAssertEqual(updated?.title, "Updated Title")
    XCTAssertEqual(updated?.items.count, 3)

    let reloaded = try await service.fetchTemplate(id: existing.id)
    XCTAssertEqual(reloaded?.title, "Updated Title")
    XCTAssertEqual(reloaded?.items.count, 3)
  }

  // MARK: - Category Support Tests

  func testAvailableCategoriesLoadedOnLoad() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()
    XCTAssertFalse(vm.availableCategories.isEmpty)
    XCTAssertNotNil(vm.selectedCategoryItem)
    XCTAssertEqual(vm.categoryId, "safety_emergency")
    XCTAssertEqual(vm.selectedCategoryItem?.id, "safety_emergency")
  }

  func testCategoryIdSelectionAndHelpers() throws {
    let service = try XCTUnwrap(checklistService)
    let vm = ChecklistTemplateDetailViewModel(
      checklistService: service,
      initialCategoryId: "routine"
    )
    XCTAssertEqual(vm.categoryId, "routine")

    vm.categoryId = "safety_emergency"
    XCTAssertEqual(vm.categoryId, "safety_emergency")

    vm.selectCategoryId("navigation_maneuver")
    XCTAssertEqual(vm.categoryId, "navigation_maneuver")

    let customItem = ChecklistCategoryItem(
      id: "custom_rigging",
      name: "Rigging",
      icon: "rope"
    )
    vm.selectCategoryItem(customItem)
    XCTAssertEqual(vm.categoryId, "custom_rigging")
  }

  func testSaveTemplateWithCustomCategory() async throws {
    let service = try XCTUnwrap(checklistService)
    let customCategory = try await service.createCategory(
      id: "custom_electronics",
      name: "Marine Electronics",
      icon: "antenna.radiowaves.left.and.right",
      sortOrder: 5
    )

    let creationVM = ChecklistTemplateDetailViewModel(
      checklistService: service,
      initialCategoryId: customCategory.id
    )
    XCTAssertEqual(creationVM.categoryId, "custom_electronics")

    creationVM.title = "NMEA Instruments Check"
    creationVM.items[0].title = "Check GPS antenna fix"
    creationVM.addItem(title: "Calibrate wind sensor")

    let saved = await creationVM.save()
    let savedTemplate = try XCTUnwrap(saved)
    XCTAssertEqual(savedTemplate.categoryId, "custom_electronics")

    let reloaded = try await service.fetchTemplate(id: savedTemplate.id)
    XCTAssertEqual(reloaded?.categoryId, "custom_electronics")
  }
}
