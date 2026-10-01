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
@testable import Sillage

@MainActor
final class ChecklistTemplateDetailViewModelTests: XCTestCase {
  private var databaseManager: DatabaseManager!
  private var checklistService: ChecklistService!
  private var template: ChecklistTemplate!
  private var viewModel: ChecklistTemplateDetailViewModel!

  override func setUp() async throws {
    try await super.setUp()
    databaseManager = try DatabaseManager.inMemory()
    checklistService = ChecklistService(
      databaseManager: databaseManager,
      throttler: ChecklistThrottler(window: .zero)
    )

    template = try await checklistService.createCustomTemplate(
      title: "Pre-Sail Brief",
      description: "Safety walkaround",
      category: .safetyEmergency,
      items: [
        (title: "Lifejackets", detail: "Count matches crew"),
        (title: "EPIRB check", detail: "Battery valid")
      ]
    )

    viewModel = ChecklistTemplateDetailViewModel(
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

  // MARK: - Consultation & Loading Tests

  func testInitialState() {
    XCTAssertEqual(viewModel.templateId, template.id)
    XCTAssertNil(viewModel.template)
    XCTAssertNil(viewModel.activeSession)
    XCTAssertNil(viewModel.latestCompletionDate)
    XCTAssertNil(viewModel.activeSessionWithProgress)
    XCTAssertEqual(viewModel.usageStatus, .neverUsed)
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(viewModel.title, "")
    XCTAssertNil(viewModel.description)
    XCTAssertEqual(viewModel.category, .routine)
    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertFalse(viewModel.hasActiveSession)
    XCTAssertFalse(viewModel.isEditable)
    XCTAssertTrue(viewModel.isEditing)
    XCTAssertTrue(viewModel.canDelete)
  }

  func testLoadTemplate() async {
    await viewModel.load()

    XCTAssertNotNil(viewModel.template)
    XCTAssertEqual(viewModel.title, "Pre-Sail Brief")
    XCTAssertEqual(viewModel.description, "Safety walkaround")
    XCTAssertEqual(viewModel.category, .safetyEmergency)
    guard viewModel.items.count == 2 else {
      XCTFail("Expected 2 items after loading")
      return
    }
    XCTAssertEqual(viewModel.items[0].title, "Lifejackets")
    XCTAssertEqual(viewModel.items[1].title, "EPIRB check")
    XCTAssertFalse(viewModel.hasActiveSession)
    XCTAssertNil(viewModel.latestCompletionDate)
    XCTAssertEqual(viewModel.usageStatus, .neverUsed)
  }

  func testUsageStatusWithActiveSessionAndProgress() async throws {
    let session = try await checklistService.startSession(templateId: template.id)
    guard let firstItem = session.items.first else {
      XCTFail("Expected session to have items")
      return
    }
    _ = try await checklistService.setItemChecked(
      sessionId: session.id,
      itemId: firstItem.id,
      isChecked: true,
      coordinate: nil
    )

    await viewModel.load()

    XCTAssertTrue(viewModel.hasActiveSession)
    XCTAssertNotNil(viewModel.activeSessionWithProgress)
    if case .inProgress(let currentSession) = viewModel.usageStatus {
      XCTAssertEqual(currentSession.id, session.id)
      XCTAssertEqual(currentSession.completedCount, 1)
    } else {
      XCTFail("Expected usageStatus to be .inProgress, got \(viewModel.usageStatus)")
    }
  }

  func testUsageStatusWithCompletedSession() async throws {
    let session = try await checklistService.startSession(templateId: template.id)
    for item in session.items {
      _ = try await checklistService.setItemChecked(
        sessionId: session.id,
        itemId: item.id,
        isChecked: true,
        coordinate: nil
      )
    }
    _ = try await checklistService.completeSession(sessionId: session.id, notes: nil)

    await viewModel.load()

    XCTAssertFalse(viewModel.hasActiveSession)
    XCTAssertNil(viewModel.activeSessionWithProgress)
    XCTAssertNotNil(viewModel.latestCompletionDate)
    if case .completed(let date) = viewModel.usageStatus {
      XCTAssertEqual(date, viewModel.latestCompletionDate)
    } else {
      XCTFail("Expected usageStatus to be .completed, got \(viewModel.usageStatus)")
    }
  }

  func testObservationUpdatesActiveAndCompletedSessions() async throws {
    let observeTask = Task { [weak viewModel] in
      await viewModel?.startObserving()
    }

    try await Task.sleep(nanoseconds: 50_000_000)

    let session = try await checklistService.startSession(templateId: template.id)
    guard let firstItem = session.items.first else {
      XCTFail("Expected session to have items")
      return
    }
    _ = try await checklistService.setItemChecked(
      sessionId: session.id,
      itemId: firstItem.id,
      isChecked: true,
      coordinate: nil
    )

    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertTrue(viewModel.hasActiveSession)
    XCTAssertNotNil(viewModel.activeSessionWithProgress)
    if case .inProgress(let currentSession) = viewModel.usageStatus {
      XCTAssertEqual(currentSession.id, session.id)
      XCTAssertEqual(currentSession.completedCount, 1)
    } else {
      XCTFail("Expected usageStatus to be .inProgress, got \(viewModel.usageStatus)")
    }

    // Complete session
    for item in session.items {
      _ = try await checklistService.setItemChecked(
        sessionId: session.id,
        itemId: item.id,
        isChecked: true,
        coordinate: nil
      )
    }
    _ = try await checklistService.completeSession(sessionId: session.id, notes: nil)

    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(viewModel.hasActiveSession)
    XCTAssertNil(viewModel.activeSessionWithProgress)
    XCTAssertNotNil(viewModel.latestCompletionDate)
    if case .completed(let date) = viewModel.usageStatus {
      XCTAssertEqual(date, viewModel.latestCompletionDate)
    } else {
      XCTFail("Expected usageStatus to be .completed, got \(viewModel.usageStatus)")
    }

    observeTask.cancel()
  }

  func testStartOrResumeSessionCreatesAndReturnsSessionId() async {
    await viewModel.load()

    let sessionId = await viewModel.startOrResumeSession()
    XCTAssertNotNil(sessionId)
    XCTAssertNotNil(viewModel.activeSession)
    XCTAssertEqual(viewModel.activeSession?.id, sessionId)
  }

  func testDeleteTemplate() async {
    await viewModel.load()

    let success = await viewModel.deleteTemplate()
    XCTAssertTrue(success)

    let reloaded = try? await checklistService.fetchTemplate(id: template.id)
    XCTAssertNil(reloaded)
  }

  // MARK: - Editing & Mutation Tests

  func testRevertRestoresOriginalValues() async {
    await viewModel.load()

    guard !viewModel.items.isEmpty else {
      XCTFail("Expected items to not be empty after loading template")
      return
    }

    viewModel.isEditable = true
    viewModel.title = "Modified Title"
    viewModel.items[0].title = "Modified Step"

    viewModel.revert()

    XCTAssertFalse(viewModel.isEditable)
    XCTAssertEqual(viewModel.title, "Pre-Sail Brief")
    guard !viewModel.items.isEmpty else {
      XCTFail("Expected items to not be empty after reverting")
      return
    }
    XCTAssertEqual(viewModel.items[0].title, "Lifejackets")
  }

  func testSaveUpdatesTemplateAndSwitchesEditMode() async {
    await viewModel.load()

    guard !viewModel.items.isEmpty else {
      XCTFail("Expected items to not be empty after loading template")
      return
    }

    viewModel.isEditable = true
    viewModel.title = "Updated Title"
    viewModel.items[0].title = "Updated Step 1"
    viewModel.addItem(title: "New Step 3")

    let saved = await viewModel.save()
    XCTAssertNotNil(saved)
    XCTAssertFalse(viewModel.isEditable)
    XCTAssertEqual(viewModel.title, "Updated Title")
    XCTAssertEqual(viewModel.items.count, 3)

    let reloaded = try? await checklistService.fetchTemplate(id: template.id)
    XCTAssertEqual(reloaded?.title, "Updated Title")
  }

  // MARK: - Creation Mode Tests

  func testCreationInitialState() {
    let creationVM = ChecklistTemplateDetailViewModel(
      checklistService: checklistService,
      initialCategory: .routine
    )

    XCTAssertNil(creationVM.templateId)
    XCTAssertFalse(creationVM.isEditing)
    XCTAssertTrue(creationVM.isEditable)
    XCTAssertTrue(creationVM.isNew)
    XCTAssertEqual(creationVM.title, "")
    XCTAssertEqual(creationVM.descriptionText, "")
    XCTAssertEqual(creationVM.category, .routine)
    XCTAssertEqual(creationVM.items.count, 1)
    XCTAssertEqual(creationVM.items.first?.title, "")
    XCTAssertFalse(creationVM.canDelete)
    XCTAssertFalse(creationVM.isValid)
    XCTAssertFalse(creationVM.isSaving)
    XCTAssertNil(creationVM.errorMessage)
  }

  func testValidationRequiresTitleAndNonEmptyItem() {
    let creationVM = ChecklistTemplateDetailViewModel(checklistService: checklistService)

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

  func testAddRemoveAndMoveItems() {
    let creationVM = ChecklistTemplateDetailViewModel(checklistService: checklistService)
    guard !creationVM.items.isEmpty else {
      XCTFail("Expected items to not be empty")
      return
    }
    creationVM.items[0].title = "Step 1"
    creationVM.addItem(title: "Step 2", detail: "Step 2 detail")
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

  func testMoveItemUpAndDown() {
    let creationVM = ChecklistTemplateDetailViewModel(checklistService: checklistService)
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

  func testSaveNewTemplate() async {
    let creationVM = ChecklistTemplateDetailViewModel(checklistService: checklistService)
    creationVM.title = "Passage Prep"
    creationVM.descriptionText = "Pre-passage safety checklist"
    creationVM.category = .safetyEmergency
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
    XCTAssertEqual(saved?.category, .safetyEmergency)
    XCTAssertEqual(saved?.items.count, 2)
    XCTAssertFalse(creationVM.isSaving)
    XCTAssertFalse(creationVM.isEditable)
    XCTAssertEqual(creationVM.templateId, saved?.id)
  }

  func testEditExistingTemplateViaDirectInit() async throws {
    let existing = try await checklistService.createCustomTemplate(
      title: "Original Title",
      description: "Original description",
      category: .routine,
      items: [
        (title: "Original Step 1", detail: "Detail 1"),
        (title: "Original Step 2", detail: "Detail 2")
      ]
    )

    let existingVM = ChecklistTemplateDetailViewModel(
      template: existing,
      checklistService: checklistService,
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

    let reloaded = try await checklistService.fetchTemplate(id: existing.id)
    XCTAssertEqual(reloaded?.title, "Updated Title")
    XCTAssertEqual(reloaded?.items.count, 3)
  }
}
