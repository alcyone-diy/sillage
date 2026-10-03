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
}
