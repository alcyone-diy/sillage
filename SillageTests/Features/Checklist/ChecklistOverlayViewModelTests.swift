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

  func testObserveActiveSessionsIncludesSessionsWithoutProgress() async throws {
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

    // Session is present even before checking any items
    try await waitUntil { vm.hasActiveChecklists && vm.activeSessions.count == 1 }

    // Checking an item activates progress
    _ = try await service.setItemChecked(
      sessionId: session.id,
      itemId: firstItem.id,
      isChecked: true
    )
    try await waitUntil { vm.completedStepsCount == 1 }

    // Deleting the session removes it -> session must no longer be in the list!
    try await service.deleteSession(sessionId: session.id)
    try await waitUntil { !vm.hasActiveChecklists && vm.activeSessions.isEmpty }
    XCTAssertFalse(vm.hasActiveChecklists)
    XCTAssertEqual(vm.activeSessions.count, 0)
    XCTAssertNil(vm.singleActiveSession)
  }

  func testObserveActiveSessionsPreservesSessionsWhenCompleted() async throws {
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

    // Session remains in the active sessions list (under completed within 48h) and is NOT removed!
    try await waitUntil { vm.completedSessions.count == 1 }
    XCTAssertEqual(vm.activeSessions.count, 1)
    XCTAssertEqual(vm.completedSessions.first?.id, session.id)
    XCTAssertTrue(vm.inProgressSessions.isEmpty)

    // But the floating checklist button must disappear from the overlay when no session is in progress
    XCTAssertFalse(vm.hasActiveChecklists)
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
    XCTAssertEqual(vm.navigationPath, [.session(ChecklistSessionPayload(id: activeSession.id, snapshot: activeSession))])

    vm.dismiss()
    XCTAssertFalse(vm.isSheetPresented)
    XCTAssertTrue(vm.navigationPath.isEmpty)
  }

  func testSessionEditorDoesNotAutoDismissWhenSessionCompletes() async throws {
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
    XCTAssertEqual(vm.navigationPath, [.session(ChecklistSessionPayload(id: activeSession.id, snapshot: activeSession))])

    // Complete session in service
    _ = try await service.completeSession(sessionId: session.id)

    // View remains presented and navigation path is NOT cleared automatically
    try await waitUntil { vm.completedSessions.count == 1 }
    XCTAssertTrue(vm.isSheetPresented)
    XCTAssertEqual(vm.navigationPath, [.session(ChecklistSessionPayload(id: activeSession.id, snapshot: activeSession))])
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
    XCTAssertEqual(vm.navigationPath, [.session(ChecklistSessionPayload(id: activeSession.id, snapshot: activeSession))])

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
    XCTAssertEqual(vm.navigationPath, [.session(ChecklistSessionPayload(id: session1.id, snapshot: session1))])

    // Complete session 1 -> session1 remains in activeSessions (under completed), sheet remains open and path is preserved
    _ = try await service.completeSession(sessionId: session1.id)
    try await waitUntil { vm.completedSessions.count == 1 }
    XCTAssertTrue(vm.isSheetPresented)
    XCTAssertEqual(vm.navigationPath, [.session(ChecklistSessionPayload(id: session1.id, snapshot: session1))])
    XCTAssertEqual(vm.activeSessions.count, 2)

    // Complete session 2 -> both remain in activeSessions, sheet remains open
    _ = try await service.completeSession(sessionId: session2.id)
    try await waitUntil { vm.completedSessions.count == 2 }
    XCTAssertTrue(vm.isSheetPresented)
    XCTAssertEqual(vm.activeSessions.count, 2)

    // User explicitly dismisses
    vm.dismiss()
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

    try await waitUntil { vm.activeSessions.count == 2 && vm.completedStepsCount == 3 }

    // Total steps across checklists: 4 + 2 = 6
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

  func testSeparationOfInProgressAndCompletedSessions() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    observationTask = Task { [weak vm, weak service] in
      guard let vm, let service else { return }
      await vm.observe(service: service)
    }

    let routineTemplate = try await service.createCustomTemplate(
      title: "Routine Checklist",
      description: nil,
      category: .routine,
      items: [("Task 1", nil)]
    )

    let engineTemplate = try await service.createCustomTemplate(
      title: "Engine Checklist",
      description: nil,
      category: .engineTechnical,
      items: [("Task 2", nil)]
    )

    let safetyTemplate = try await service.createCustomTemplate(
      title: "Safety Checklist",
      description: nil,
      category: .safetyEmergency,
      items: [("Task 3", nil)]
    )

    // Complete routine and engine sessions
    let routineSession = try await service.startSession(templateId: routineTemplate.id)
    _ = try await service.setItemChecked(sessionId: routineSession.id, itemId: routineSession.items[0].id, isChecked: true)
    _ = try await service.completeSession(sessionId: routineSession.id)

    let engineSession = try await service.startSession(templateId: engineTemplate.id)
    _ = try await service.setItemChecked(sessionId: engineSession.id, itemId: engineSession.items[0].id, isChecked: true)
    _ = try await service.completeSession(sessionId: engineSession.id)

    // Leave safety session in progress
    let safetySession = try await service.startSession(templateId: safetyTemplate.id)

    try await waitUntil { vm.activeSessions.count == 3 }

    XCTAssertEqual(vm.inProgressSessions.count, 1)
    XCTAssertEqual(vm.inProgressSessions.first?.id, safetySession.id)
    XCTAssertTrue(vm.hasActiveChecklists)

    XCTAssertEqual(vm.completedSessions.count, 2)
    XCTAssertTrue(vm.completedSessions.contains(where: { $0.id == routineSession.id }))
    XCTAssertTrue(vm.completedSessions.contains(where: { $0.id == engineSession.id }))

    // Once the last in-progress session is completed, hasActiveChecklists becomes false
    _ = try await service.completeSession(sessionId: safetySession.id)
    try await waitUntil { vm.completedSessions.count == 3 }
    XCTAssertFalse(vm.hasActiveChecklists)
    XCTAssertEqual(vm.activeSessions.count, 3)
  }

  func testSessionsSortedAlphabetically() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    observationTask = Task { [weak vm, weak service] in
      guard let vm, let service else { return }
      await vm.observe(service: service)
    }

    let templateZ = try await service.createCustomTemplate(
      title: "Zulu Checklist",
      description: nil,
      category: .routine,
      items: [("Z1", nil)]
    )
    let templateA = try await service.createCustomTemplate(
      title: "Alpha Checklist",
      description: nil,
      category: .routine,
      items: [("A1", nil)]
    )
    let templateB = try await service.createCustomTemplate(
      title: "Bravo Checklist",
      description: nil,
      category: .routine,
      items: [("B1", nil)]
    )

    let sessionZ = try await service.startSession(templateId: templateZ.id)
    let sessionA = try await service.startSession(templateId: templateA.id)
    let sessionB = try await service.startSession(templateId: templateB.id)

    _ = try await service.setItemChecked(sessionId: sessionZ.id, itemId: sessionZ.items[0].id, isChecked: true)
    _ = try await service.setItemChecked(sessionId: sessionA.id, itemId: sessionA.items[0].id, isChecked: true)
    _ = try await service.setItemChecked(sessionId: sessionB.id, itemId: sessionB.items[0].id, isChecked: true)

    try await waitUntil { vm.inProgressSessions.count == 3 }

    XCTAssertEqual(
      vm.inProgressSessions.map(\.templateTitleSnapshot),
      ["Alpha Checklist", "Bravo Checklist", "Zulu Checklist"]
    )

    // Complete session Z and session A
    _ = try await service.completeSession(sessionId: sessionZ.id)
    _ = try await service.completeSession(sessionId: sessionA.id)

    try await waitUntil { vm.completedSessions.count == 2 && vm.inProgressSessions.count == 1 }

    XCTAssertEqual(
      vm.completedSessions.map(\.templateTitleSnapshot),
      ["Alpha Checklist", "Zulu Checklist"]
    )
  }

  func testTemplateDeletionUpdatesSessionsAndActiveChecklists() async throws {
    let service = try XCTUnwrap(checklistService)
    let vm = try XCTUnwrap(viewModel)

    observationTask = Task { [weak vm, weak service] in
      guard let vm, let service else { return }
      await vm.observe(service: service)
    }

    let template = try await service.createCustomTemplate(
      title: "Temporary Checklist",
      description: nil,
      category: .routine,
      items: [("Step 1", nil)]
    )

    _ = try await service.startSession(templateId: template.id)
    try await waitUntil { vm.activeSessions.count == 1 && vm.hasActiveChecklists }

    // Delete the template from the service
    try await service.deleteCustomTemplate(id: template.id)

    // DB stream updates sessions and active checklist state without side-effect mutations on navigationPath
    try await waitUntil { vm.activeSessions.isEmpty }
    XCTAssertTrue(vm.activeSessions.isEmpty)
    XCTAssertFalse(vm.hasActiveChecklists)
  }

  // MARK: - Navigation Identity Tests

  func testDestinationEqualityIgnoresMutableSessionSnapshot() {
    let sessionId = UUID()
    let templateId = UUID()

    let initialSession = ChecklistSession(
      id: sessionId,
      templateId: templateId,
      templateTitleSnapshot: "Safety Briefing",
      category: .safetyEmergency,
      status: .inProgress,
      items: [
        ChecklistSessionItem(
          sessionId: sessionId,
          sourceTemplateItemId: UUID(),
          sortOrder: 0,
          title: "Lifejackets",
          isChecked: false
        )
      ]
    )

    let mutatedSession = ChecklistSession(
      id: sessionId,
      templateId: templateId,
      templateTitleSnapshot: "Safety Briefing",
      category: .safetyEmergency,
      status: .completed,
      items: [
        ChecklistSessionItem(
          sessionId: sessionId,
          sourceTemplateItemId: UUID(),
          sortOrder: 0,
          title: "Lifejackets",
          isChecked: true
        )
      ]
    )

    let payload1 = ChecklistSessionPayload(id: sessionId, snapshot: initialSession)
    let payload2 = ChecklistSessionPayload(id: sessionId, snapshot: mutatedSession)
    let payloadWithoutSnapshot = ChecklistSessionPayload(id: sessionId)
    let payloadDifferentId = ChecklistSessionPayload(id: UUID(), snapshot: initialSession)

    // Payload equality relies exclusively on id
    XCTAssertEqual(payload1, payload2)
    XCTAssertEqual(payload1, payloadWithoutSnapshot)
    XCTAssertNotEqual(payload1, payloadDifferentId)

    // Payload hash consistency relies exclusively on id
    var hasher1 = Hasher()
    payload1.hash(into: &hasher1)
    var hasher2 = Hasher()
    payload2.hash(into: &hasher2)
    var hasherWithout = Hasher()
    payloadWithoutSnapshot.hash(into: &hasherWithout)
    XCTAssertEqual(hasher1.finalize(), hasher2.finalize())
    XCTAssertEqual(hasher1.finalize(), hasherWithout.finalize())

    let destination1 = ChecklistOverlayDestination.session(payload1)
    let destination2 = ChecklistOverlayDestination.session(payload2)
    let destinationWithoutSnapshot = ChecklistOverlayDestination.session(payloadWithoutSnapshot)
    let destinationDifferentId = ChecklistOverlayDestination.session(payloadDifferentId)

    // Synthesized destination equality relies on payload's id
    XCTAssertEqual(destination1, destination2)
    XCTAssertEqual(destination1, destinationWithoutSnapshot)
    XCTAssertNotEqual(destination1, destinationDifferentId)

    // In a navigation path, re-selecting mutatedSession when initialSession is already present is cleanly prevented
    let vm = ChecklistOverlayViewModel()
    vm.selectSession(initialSession)
    XCTAssertEqual(vm.navigationPath.count, 1)

    vm.selectSession(mutatedSession)
    XCTAssertEqual(vm.navigationPath.count, 1)
  }
}
