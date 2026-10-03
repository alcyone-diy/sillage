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
    XCTAssertTrue(vm.groupedTemplates.isEmpty)
  }

  // MARK: - Loading Templates Tests

  func testLoadTemplates() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    _ = try await service.createCustomTemplate(
      title: "Routine Check",
      description: "Routine items",
      category: .routine,
      items: [("Item 1", "Detail 1")]
    )
    _ = try await service.createCustomTemplate(
      title: "Safety Brief",
      description: "Emergency equipment",
      category: .safetyEmergency,
      items: [("Lifejackets", "On deck")]
    )

    await vm.loadTemplates()

    XCTAssertEqual(vm.templates.count, 2)
    XCTAssertEqual(vm.groupedTemplates.count, 2)
    XCTAssertNil(vm.errorMessage)
  }

  // MARK: - Active Sessions Observation Tests

  func testActiveSessionsTracking() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    let template = try await service.createCustomTemplate(
      title: "Navigation Prep",
      description: nil,
      category: .navigationManeuver,
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
      category: .routine,
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
      category: .routine,
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
}
