//
//  ChecklistOverlayViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class ChecklistOverlayViewModelTests: XCTestCase {
  private var databaseManager: DatabaseManager?
  private var checklistService: ChecklistService?
  private var viewModel: ChecklistOverlayViewModel?
  private var observationTask: Task<Void, Never>?

  override func setUp() async throws {
    try await super.setUp()
    let dbManager = try DatabaseManager.inMemory()
    let service = ChecklistService(
      databaseManager: dbManager,
      throttler: ChecklistThrottler(window: .zero)
    )
    self.databaseManager = dbManager
    self.checklistService = service
    self.viewModel = ChecklistOverlayViewModel()
  }

  override func tearDown() async throws {
    observationTask?.cancel()
    observationTask = nil
    viewModel = nil
    checklistService = nil
    databaseManager = nil
    try await super.tearDown()
  }

  // MARK: - Initial State Tests

  func testInitialState() throws {
    let vm = try XCTUnwrap(viewModel)
    XCTAssertTrue(vm.activeSessions.isEmpty)
    XCTAssertFalse(vm.hasActiveChecklists)
    XCTAssertNil(vm.singleActiveSession)
    XCTAssertEqual(vm.completedStepsCount, 0)
    XCTAssertEqual(vm.totalStepsCount, 0)
    XCTAssertEqual(vm.progressRatio, 0.0)
    XCTAssertFalse(vm.isSheetPresented)
    XCTAssertTrue(vm.navigationPath.isEmpty)
  }

  // MARK: - Reactive Observation & Business Filtering Tests

  func testObserveActiveSessionsIgnoresSessionsWithoutProgress() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    observationTask = Task { [weak vm, weak service] in
      guard let vm, let service else { return }
      await vm.observe(service: service)
    }

    // Create a template
    let template = try await service.createCustomTemplate(
      title: "Engine Check",
      description: nil,
      category: .engineTechnical,
      items: [("Check oil", nil)]
    )

    // Start a session
    let session = try await service.startSession(templateId: template.id)
    guard let firstItem = session.items.first else {
      XCTFail("Expected at least one item")
      return
    }

    // Checking an item activates it
    _ = try await service.setItemChecked(
      sessionId: session.id,
      itemId: firstItem.id,
      isChecked: true
    )
    try await waitUntil { vm.hasActiveChecklists && vm.activeSessions.count == 1 }

    // Resetting the session clears checks to 0 -> must become inactive
    _ = try await service.resetSession(sessionId: session.id)
    try await waitUntil { !vm.hasActiveChecklists && vm.activeSessions.isEmpty }
    XCTAssertNil(vm.singleActiveSession)
  }

  func testObserveActiveSessionsShowsWhenProgressExistsAndHidesWhenCompleted() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    observationTask = Task { [weak vm, weak service] in
      guard let vm, let service else { return }
      await vm.observe(service: service)
    }

    let template = try await service.createCustomTemplate(
      title: "Mooring Prep",
      description: nil,
      category: .routine,
      items: [("Prepare lines", nil), ("Fenders out", nil)]
    )

    let session = try await service.startSession(templateId: template.id)
    guard let firstItem = session.items.first else {
      XCTFail("Expected at least one item")
      return
    }

    // Check first item -> completedCount becomes 1
    _ = try await service.setItemChecked(
      sessionId: session.id,
      itemId: firstItem.id,
      isChecked: true
    )

    // Robust expectation with timeout
    try await waitUntil { vm.hasActiveChecklists && vm.activeSessions.count == 1 }
    XCTAssertEqual(vm.singleActiveSession?.id, session.id)

    // Complete session
    _ = try await service.completeSession(sessionId: session.id)

    // Robust expectation for completion
    try await waitUntil { !vm.hasActiveChecklists && vm.activeSessions.isEmpty }
    XCTAssertNil(vm.singleActiveSession)
  }

  func testMultipleActiveSessions() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    observationTask = Task { [weak vm, weak service] in
      guard let vm, let service else { return }
      await vm.observe(service: service)
    }

    let template1 = try await service.createCustomTemplate(
      title: "Checklist 1",
      description: nil,
      category: .routine,
      items: [("Item 1", nil)]
    )
    let template2 = try await service.createCustomTemplate(
      title: "Checklist 2",
      description: nil,
      category: .safetyEmergency,
      items: [("Item A", nil)]
    )

    let session1 = try await service.startSession(templateId: template1.id)
    let session2 = try await service.startSession(templateId: template2.id)

    // Check an item in both
    _ = try await service.setItemChecked(sessionId: session1.id, itemId: session1.items[0].id, isChecked: true)
    _ = try await service.setItemChecked(sessionId: session2.id, itemId: session2.items[0].id, isChecked: true)

    try await waitUntil { vm.hasActiveChecklists && vm.activeSessions.count == 2 }
    XCTAssertNil(vm.singleActiveSession)
  }

  func testPresentationControls() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    observationTask = Task { [weak vm, weak service] in
      guard let vm, let service else { return }
      await vm.observe(service: service)
    }

    let template = try await service.createCustomTemplate(
      title: "Engine Check",
      description: nil,
      category: .engineTechnical,
      items: [("Check oil", nil)]
    )

    let session = try await service.startSession(templateId: template.id)
    _ = try await service.setItemChecked(
      sessionId: session.id,
      itemId: session.items[0].id,
      isChecked: true
    )

    try await waitUntil { vm.singleActiveSession != nil }
    let activeSession = try XCTUnwrap(vm.singleActiveSession)

    XCTAssertFalse(vm.isSheetPresented)
    XCTAssertTrue(vm.navigationPath.isEmpty)

    vm.openActiveChecklists()
    XCTAssertTrue(vm.isSheetPresented)
    XCTAssertEqual(vm.navigationPath, [activeSession.id])

    vm.dismiss()
    XCTAssertFalse(vm.isSheetPresented)
    XCTAssertTrue(vm.navigationPath.isEmpty)
  }

  func testAutoDismissWhenSessionCompletes() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    observationTask = Task { [weak vm, weak service] in
      guard let vm, let service else { return }
      await vm.observe(service: service)
    }

    let template = try await service.createCustomTemplate(
      title: "Pre-departure Check",
      description: nil,
      category: .routine,
      items: [("Check bilge", nil)]
    )

    let session = try await service.startSession(templateId: template.id)
    _ = try await service.setItemChecked(
      sessionId: session.id,
      itemId: session.items[0].id,
      isChecked: true
    )

    try await waitUntil { vm.singleActiveSession != nil }
    let activeSession = try XCTUnwrap(vm.singleActiveSession)

    // Open session in sheet
    vm.openActiveChecklists()
    XCTAssertTrue(vm.isSheetPresented)
    XCTAssertEqual(vm.navigationPath, [activeSession.id])

    // Complete session in service
    _ = try await service.completeSession(sessionId: session.id)

    // Automatically dismissed via reactive synchronization
    try await waitUntil { !vm.isSheetPresented && vm.navigationPath.isEmpty }
    XCTAssertFalse(vm.isSheetPresented)
    XCTAssertTrue(vm.navigationPath.isEmpty)
  }

  func testOpenActiveChecklistsRoutesToSingleWhenOnlyOneActive() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    observationTask = Task { [weak vm, weak service] in
      guard let vm, let service else { return }
      await vm.observe(service: service)
    }

    let template = try await service.createCustomTemplate(
      title: "Solo Check",
      description: nil,
      category: .routine,
      items: [("Check mast", nil)]
    )

    let session = try await service.startSession(templateId: template.id)
    _ = try await service.setItemChecked(
      sessionId: session.id,
      itemId: session.items[0].id,
      isChecked: true
    )

    try await waitUntil { vm.singleActiveSession != nil }
    let activeSession = try XCTUnwrap(vm.singleActiveSession)

    vm.openActiveChecklists()
    XCTAssertTrue(vm.isSheetPresented)
    XCTAssertEqual(vm.navigationPath, [activeSession.id])

    vm.dismiss()
    XCTAssertFalse(vm.isSheetPresented)
    XCTAssertTrue(vm.navigationPath.isEmpty)
  }

  func testOpenActiveChecklistsRoutesToListWhenMultipleActive() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    observationTask = Task { [weak vm, weak service] in
      guard let vm, let service else { return }
      await vm.observe(service: service)
    }

    let template1 = try await service.createCustomTemplate(
      title: "Check 1",
      description: nil,
      category: .routine,
      items: [("Item 1", nil)]
    )
    let template2 = try await service.createCustomTemplate(
      title: "Check 2",
      description: nil,
      category: .routine,
      items: [("Item 2", nil)]
    )

    let session1 = try await service.startSession(templateId: template1.id)
    let session2 = try await service.startSession(templateId: template2.id)

    _ = try await service.setItemChecked(sessionId: session1.id, itemId: session1.items[0].id, isChecked: true)
    _ = try await service.setItemChecked(sessionId: session2.id, itemId: session2.items[0].id, isChecked: true)

    try await waitUntil { vm.activeSessions.count == 2 }

    // Opens sheet with empty navigationPath (showing the list root)
    vm.openActiveChecklists()
    XCTAssertTrue(vm.isSheetPresented)
    XCTAssertTrue(vm.navigationPath.isEmpty)

    // User selects session 1
    vm.selectSession(session1)
    XCTAssertEqual(vm.navigationPath, [session1.id])

    // Complete session 1 -> navigationPath filters out session1, pops back to list (path empty), sheet remains open
    _ = try await service.completeSession(sessionId: session1.id)
    try await waitUntil { vm.activeSessions.count == 1 }
    try await waitUntil { vm.navigationPath.isEmpty }
    XCTAssertTrue(vm.isSheetPresented)
    XCTAssertTrue(vm.navigationPath.isEmpty)

    // Complete session 2 -> activeSessions becomes empty -> sheet auto-dismisses
    _ = try await service.completeSession(sessionId: session2.id)
    try await waitUntil { vm.activeSessions.isEmpty }
    try await waitUntil { !vm.isSheetPresented }
    XCTAssertFalse(vm.isSheetPresented)
    XCTAssertTrue(vm.navigationPath.isEmpty)
  }

  func testProgressMetricsAcrossActiveSessions() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    observationTask = Task { [weak vm, weak service] in
      guard let vm, let service else { return }
      await vm.observe(service: service)
    }

    let template1 = try await service.createCustomTemplate(
      title: "Check 1",
      description: nil,
      category: .routine,
      items: [("Item 1A", nil), ("Item 1B", nil), ("Item 1C", nil), ("Item 1D", nil)]
    )
    let template2 = try await service.createCustomTemplate(
      title: "Check 2",
      description: nil,
      category: .navigationManeuver,
      items: [("Item 2A", nil), ("Item 2B", nil)]
    )

    let session1 = try await service.startSession(templateId: template1.id)
    let session2 = try await service.startSession(templateId: template2.id)

    // Check 2 items on session1 (out of 4)
    _ = try await service.setItemChecked(sessionId: session1.id, itemId: session1.items[0].id, isChecked: true)
    _ = try await service.setItemChecked(sessionId: session1.id, itemId: session1.items[1].id, isChecked: true)

    // Check 1 item on session2 (out of 2)
    _ = try await service.setItemChecked(sessionId: session2.id, itemId: session2.items[0].id, isChecked: true)

    try await waitUntil { vm.activeSessions.count == 2 }

    // Total steps across non-completed checklists: 4 + 2 = 6
    // Completed steps: 2 + 1 = 3
    // Progress ratio: 3 / 6 = 0.5
    XCTAssertEqual(vm.completedStepsCount, 3)
    XCTAssertEqual(vm.totalStepsCount, 6)
    XCTAssertEqual(vm.progressRatio, 0.5, accuracy: 0.001)

    // Check another item on session1 -> 4 completed out of 6 -> 0.666...
    _ = try await service.setItemChecked(sessionId: session1.id, itemId: session1.items[2].id, isChecked: true)
    try await waitUntil { vm.completedStepsCount == 4 }

    XCTAssertEqual(vm.completedStepsCount, 4)
    XCTAssertEqual(vm.totalStepsCount, 6)
    XCTAssertEqual(vm.progressRatio, 4.0 / 6.0, accuracy: 0.001)
  }
}
