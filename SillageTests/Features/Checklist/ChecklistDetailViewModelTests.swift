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
import CoreLocation
@testable import Sillage

@MainActor
final class ChecklistDetailViewModelTests: XCTestCase {
  private var databaseManager: DatabaseManager!
  private var checklistService: ChecklistService!
  private var template: ChecklistTemplate!
  private var viewModel: ChecklistDetailViewModel!
  private var simulatedFix: NavigationFix?
  private var observeTask: Task<Void, Never>?

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
        (title: "Check oil level", detail: "Dipstick between MIN and MAX"),
        (title: "Check raw water strainer", detail: "Free of weed and debris"),
        (title: "Visual belt check", detail: "Check tension and wear")
      ]
    )

    viewModel = ChecklistDetailViewModel(
      templateId: template.id,
      checklistService: checklistService,
      locationProvider: { [weak self] in
        self?.simulatedFix
      }
    )
  }

  override func tearDown() async throws {
    observeTask?.cancel()
    observeTask = nil
    viewModel = nil
    simulatedFix = nil
    template = nil
    checklistService = nil
    databaseManager = nil
    try await super.tearDown()
  }

  // MARK: - Load & Lazy Session Initialization Tests

  func testLoadLoadsTemplateWithoutImmediateSession() async {
    XCTAssertNil(viewModel.template)
    XCTAssertNil(viewModel.session)

    await viewModel.load()

    XCTAssertNotNil(viewModel.template)
    // Lazy: session is NOT created in DB until the user checks the first item
    XCTAssertNil(viewModel.session)
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

    // Checking the first item creates the session on demand with startedAt
    guard let firstItem = viewModel.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    await viewModel.toggleItem(firstItem)

    XCTAssertNotNil(viewModel.session)
    XCTAssertEqual(viewModel.completedCount, 1)
    XCTAssertNotNil(viewModel.session?.startedAt)
  }

  // MARK: - Reactive Stream Observation Tests

  func testReactiveObservationDrivesItemToggle() async throws {
    await viewModel.load()
    observeTask = Task { [weak viewModel] in
      await viewModel?.observe()
    }

    // Give observation time to connect
    try await Task.sleep(nanoseconds: 50_000_000)

    guard let firstItem = viewModel.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    XCTAssertFalse(firstItem.isChecked)

    await viewModel.toggleItem(firstItem)

    // Wait for DB observation stream to yield
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertEqual(viewModel.completedCount, 1)
    XCTAssertEqual(viewModel.progressRatio, 1.0 / 3.0)
    XCTAssertTrue(viewModel.items.first?.isChecked == true)

    // Reset via service/VM
    await viewModel.reset()
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertEqual(viewModel.completedCount, 0)
    XCTAssertTrue(viewModel.items.first?.isChecked == false)
  }

  // MARK: - Progressive Disclosure (Current Item) Tests

  func testProgressiveDisclosureCurrentItem() async {
    await viewModel.load()
    observeTask = Task { [weak viewModel] in
      await viewModel?.observe()
    }

    // Initial: First unchecked item is item 0
    XCTAssertEqual(viewModel.currentItemId, viewModel.items[0].stableId)

    // Toggle item 0 via viewModel (lazily instantiates session)
    await viewModel.toggleItem(viewModel.items[0])
    try? await Task.sleep(nanoseconds: 100_000_000)

    guard let session = viewModel.session else {
      XCTFail("Session must exist after toggle")
      return
    }

    // Next unchecked item is item 1
    XCTAssertEqual(viewModel.currentItemId, session.items[1].stableId)

    // Toggle items 1 and 2
    _ = try? await checklistService.setItemChecked(
      sessionId: session.id,
      itemId: session.items[1].id,
      isChecked: true,
      coordinate: nil
    )
    _ = try? await checklistService.setItemChecked(
      sessionId: session.id,
      itemId: session.items[2].id,
      isChecked: true,
      coordinate: nil
    )

    try? await Task.sleep(nanoseconds: 100_000_000)

    // All checked: currentItemId is nil
    XCTAssertNil(viewModel.currentItemId)
  }

  // MARK: - Defensive GPS Accuracy Injection Tests

  func testDefensiveGPSAccuracyAcceptsUnder50Meters() async throws {
    await viewModel.load()

    // Accurate fix (15 meters <= 50m)
    let expectedCoord = CLLocationCoordinate2D(latitude: 46.159, longitude: -1.152)
    simulatedFix = NavigationFix(
      coordinate: expectedCoord,
      horizontalAccuracy: Measurement(value: 15.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )

    guard let firstItem = viewModel.items.first else {
      XCTFail("Missing item")
      return
    }

    await viewModel.toggleItem(firstItem)

    guard let session = viewModel.session else {
      XCTFail("Missing session after toggle")
      return
    }

    let updatedSession = try await checklistService.fetchSession(id: session.id)
    let updatedItem = updatedSession?.items.first { $0.id == firstItem.id || $0.sourceTemplateItemId == firstItem.id }
    XCTAssertNotNil(updatedItem?.coordinate)
    XCTAssertEqual(updatedItem?.coordinate?.latitude, 46.159)
    XCTAssertEqual(updatedItem?.coordinate?.longitude, -1.152)
  }

  func testDefensiveGPSAccuracyRejectsOver50Meters() async throws {
    await viewModel.load()

    // Degraded fix (65 meters > 50m)
    simulatedFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 46.159, longitude: -1.152),
      horizontalAccuracy: Measurement(value: 65.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )

    guard let firstItem = viewModel.items.first else {
      XCTFail("Missing item")
      return
    }

    await viewModel.toggleItem(firstItem)

    guard let session = viewModel.session else {
      XCTFail("Missing session after toggle")
      return
    }

    let updatedSession = try await checklistService.fetchSession(id: session.id)
    let updatedItem = updatedSession?.items.first { $0.id == firstItem.id || $0.sourceTemplateItemId == firstItem.id }
    XCTAssertTrue(updatedItem?.isChecked == true)
    XCTAssertNil(updatedItem?.coordinate)
  }

  // MARK: - Completion Tests

  func testCompleteSession() async throws {
    await viewModel.load()
    observeTask = Task { [weak viewModel] in
      await viewModel?.observe()
    }
    try await Task.sleep(nanoseconds: 50_000_000)

    XCTAssertFalse(viewModel.canComplete)
    XCTAssertFalse(viewModel.isCompleted)

    guard let firstItem = viewModel.items.first else {
      XCTFail("Missing first item")
      return
    }
    await viewModel.toggleItem(firstItem)
    try await Task.sleep(nanoseconds: 50_000_000)

    guard let session = viewModel.session else {
      XCTFail("Session missing after toggle")
      return
    }

    for item in session.items where !item.isChecked {
      _ = try await checklistService.setItemChecked(
        sessionId: session.id,
        itemId: item.id,
        isChecked: true,
        coordinate: nil
      )
    }
    try await Task.sleep(nanoseconds: 50_000_000)

    XCTAssertTrue(viewModel.canComplete)

    await viewModel.complete()
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertTrue(viewModel.isCompleted)
    XCTAssertFalse(viewModel.canComplete)
  }

  func testStartedAtRecordedAtFirstCheckAndReset() async throws {
    await viewModel.load()
    XCTAssertNil(viewModel.session)

    let beforeFirstCheck = Date()
    guard let firstItem = viewModel.items.first else {
      XCTFail("Missing first item")
      return
    }

    await viewModel.toggleItem(firstItem)
    guard let session = viewModel.session else {
      XCTFail("Session should be created on first check")
      return
    }

    XCTAssertGreaterThanOrEqual(session.startedAt, beforeFirstCheck)

    // Reset session
    await viewModel.reset()
    XCTAssertEqual(viewModel.completedCount, 0)

    try await Task.sleep(nanoseconds: 20_000_000)
    let beforeSecondCheck = Date()

    guard let itemAfterReset = viewModel.items.first else {
      XCTFail("Missing item after reset")
      return
    }
    await viewModel.toggleItem(itemAfterReset)

    guard let sessionAfterReset = viewModel.session else {
      XCTFail("Session should exist")
      return
    }
    XCTAssertGreaterThanOrEqual(sessionAfterReset.startedAt, beforeSecondCheck)
  }

  // MARK: - Cascade Deletion Tests

  func testDeleteCustomTemplateWithSessionHistorySucceeds() async {
    await viewModel.load()

    // With cascade deletion, deleting this template succeeds even with active/historical sessions
    let success = await viewModel.deleteTemplate()
    XCTAssertTrue(success)
    XCTAssertNil(viewModel.errorMessage)

    // Template is deleted from DB
    let fetched = try? await checklistService.fetchTemplate(id: template.id)
    XCTAssertNil(fetched)
  }

  func testDeleteCustomTemplateWithoutSessionHistorySucceeds() async throws {
    let freshTemplate = try await checklistService.createCustomTemplate(
      title: "Fresh Unexecuted",
      description: nil,
      category: .routine,
      items: [("Task", nil)]
    )

    let freshVM = ChecklistDetailViewModel(
      templateId: freshTemplate.id,
      checklistService: checklistService
    )

    // Before load() (no session created)
    freshVM.template = freshTemplate
    let success = await freshVM.deleteTemplate()
    XCTAssertTrue(success)
    XCTAssertNil(freshVM.errorMessage)

    let fetched = try await checklistService.fetchTemplate(id: freshTemplate.id)
    XCTAssertNil(fetched)
  }

  // MARK: - Template Refresh Tests

  func testRefreshTemplateRefreshesReorderedSessionItems() async throws {
    await viewModel.load()
    XCTAssertEqual(viewModel.items.count, 3)
    XCTAssertEqual(viewModel.items[0].title, "Check oil level")
    XCTAssertEqual(viewModel.items[1].title, "Check raw water strainer")
    XCTAssertEqual(viewModel.items[2].title, "Visual belt check")

    // Reorder template items: item 2 first, then item 0, then item 1
    let reorderedItems = [
      (id: Optional(template.items[2].id), title: "Visual belt check", detail: template.items[2].detail),
      (id: Optional(template.items[0].id), title: "Check oil level", detail: template.items[0].detail),
      (id: Optional(template.items[1].id), title: "Check raw water strainer", detail: template.items[1].detail)
    ]

    _ = try await checklistService.updateTemplate(
      id: template.id,
      title: template.title,
      description: template.description,
      category: template.category,
      items: reorderedItems
    )

    await viewModel.refreshTemplate()

    XCTAssertEqual(viewModel.items.count, 3)
    XCTAssertEqual(viewModel.items[0].title, "Visual belt check")
    XCTAssertEqual(viewModel.items[1].title, "Check oil level")
    XCTAssertEqual(viewModel.items[2].title, "Check raw water strainer")
  }
}

