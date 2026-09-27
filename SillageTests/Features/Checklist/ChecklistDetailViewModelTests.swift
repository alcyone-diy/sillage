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
  }

  // MARK: - Reactive Stream Observation Tests

  func testReactiveObservationDrivesItemToggle() async throws {
    await viewModel.load()
    observeTask = Task { [viewModel] in
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
    observeTask = Task { [viewModel] in
      await viewModel?.observe()
    }

    // Initial: First unchecked item is item 0
    XCTAssertEqual(viewModel.currentItemId, viewModel.items[0].id)

    // Toggle item 0 directly in DB
    guard let execution = viewModel.execution else {
      XCTFail("Execution must exist")
      return
    }
    _ = try? await checklistService.setItemChecked(
      executionId: execution.id,
      itemId: viewModel.items[0].id,
      isChecked: true,
      coordinate: nil
    )

    try? await Task.sleep(nanoseconds: 100_000_000)

    // Next unchecked item is item 1
    XCTAssertEqual(viewModel.currentItemId, viewModel.items[1].id)

    // Toggle items 1 and 2
    _ = try? await checklistService.setItemChecked(
      executionId: execution.id,
      itemId: viewModel.items[1].id,
      isChecked: true,
      coordinate: nil
    )
    _ = try? await checklistService.setItemChecked(
      executionId: execution.id,
      itemId: viewModel.items[2].id,
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

    guard let firstItem = viewModel.items.first, let execution = viewModel.execution else {
      XCTFail("Missing item or execution")
      return
    }

    await viewModel.toggleItem(firstItem)

    let updatedExecution = try await checklistService.fetchExecution(id: execution.id)
    let updatedItem = updatedExecution?.items.first { $0.id == firstItem.id }
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

    guard let firstItem = viewModel.items.first, let execution = viewModel.execution else {
      XCTFail("Missing item or execution")
      return
    }

    await viewModel.toggleItem(firstItem)

    let updatedExecution = try await checklistService.fetchExecution(id: execution.id)
    let updatedItem = updatedExecution?.items.first { $0.id == firstItem.id }
    XCTAssertTrue(updatedItem?.isChecked == true)
    XCTAssertNil(updatedItem?.coordinate)
  }

  // MARK: - Completion Tests

  func testCompleteExecution() async throws {
    await viewModel.load()
    observeTask = Task { [viewModel] in
      await viewModel?.observe()
    }
    try await Task.sleep(nanoseconds: 50_000_000)

    guard let execution = viewModel.execution else {
      XCTFail("Execution missing")
      return
    }

    XCTAssertFalse(viewModel.canComplete)
    XCTAssertFalse(viewModel.isCompleted)

    for item in viewModel.items {
      _ = try await checklistService.setItemChecked(
        executionId: execution.id,
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

  // MARK: - Auditability (Delete Rejection) Tests

  func testDeleteCustomTemplateWithExecutionHistoryFails() async {
    await viewModel.load()

    // Since load() started an in_progress execution session, deleting this template must fail
    let success = await viewModel.deleteTemplate()
    XCTAssertFalse(success)
    XCTAssertNotNil(viewModel.errorMessage)

    // Template still exists in DB
    let fetched = try? await checklistService.fetchTemplate(id: template.id)
    XCTAssertNotNil(fetched)
  }

  func testDeleteCustomTemplateWithoutExecutionHistorySucceeds() async throws {
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

    // Before load() (no execution created)
    freshVM.template = freshTemplate
    let success = await freshVM.deleteTemplate()
    XCTAssertTrue(success)
    XCTAssertNil(freshVM.errorMessage)

    let fetched = try await checklistService.fetchTemplate(id: freshTemplate.id)
    XCTAssertNil(fetched)
  }
}
