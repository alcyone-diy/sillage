//
//  ChecklistSessionViewModelTests.swift
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
final class ChecklistSessionViewModelTests: XCTestCase {
  private var databaseManager: DatabaseManager!
  private var checklistService: ChecklistService!
  private var template: ChecklistTemplate!
  private var session: ChecklistSession!
  private var viewModel: ChecklistSessionViewModel!
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

    session = try await checklistService.startSession(templateId: template.id)

    viewModel = ChecklistSessionViewModel(
      sessionId: session.id,
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
    session = nil
    template = nil
    checklistService = nil
    databaseManager = nil
    try await super.tearDown()
  }

  // MARK: - Load Tests

  func testInitWithPreloadedSessionExposesTitleInstantly() {
    let preloadedVM = ChecklistSessionViewModel(
      sessionId: session.id,
      session: session,
      checklistService: checklistService
    )

    XCTAssertEqual(preloadedVM.title, "Engine Check")
    XCTAssertEqual(preloadedVM.items.count, 3)
    XCTAssertFalse(preloadedVM.title.isEmpty)
    XCTAssertNotNil(preloadedVM.session)
  }

  func testLoadFetchesSessionAndTemplate() async {
    XCTAssertNil(viewModel.session)
    XCTAssertNil(viewModel.template)

    await viewModel.load()

    XCTAssertNotNil(viewModel.session)
    XCTAssertNotNil(viewModel.template)
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

  // MARK: - Toggle Item & GPS Audit Tests

  func testToggleItemWithAccurateLocationAuditing() async throws {
    await viewModel.load()

    simulatedFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 47.654, longitude: -3.123),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )

    guard let firstItem = viewModel.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    await viewModel.toggleItem(firstItem)

    XCTAssertEqual(viewModel.completedCount, 1)
    XCTAssertTrue(viewModel.canReset)
    XCTAssertFalse(viewModel.canComplete)

    let updatedItem = viewModel.items.first(where: { $0.id == firstItem.id })
    XCTAssertTrue(updatedItem?.isChecked == true)
    XCTAssertNotNil(updatedItem?.checkedAt)
    XCTAssertEqual(updatedItem?.coordinate?.latitude ?? 0, 47.654, accuracy: 0.0001)
    XCTAssertEqual(updatedItem?.coordinate?.longitude ?? 0, -3.123, accuracy: 0.0001)
  }

  func testToggleItemRejectsInaccurateGPSFix() async throws {
    await viewModel.load()

    // Accuracy 55m > 50m threshold -> coordinate must be dropped
    simulatedFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 47.654, longitude: -3.123),
      horizontalAccuracy: Measurement(value: 55.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )

    guard let firstItem = viewModel.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    await viewModel.toggleItem(firstItem)

    let updatedItem = viewModel.items.first(where: { $0.id == firstItem.id })
    XCTAssertTrue(updatedItem?.isChecked == true)
    XCTAssertNil(updatedItem?.coordinate)
  }

  func testToggleItemDoesNotTriggerIsPerformingAction() async {
    await viewModel.load()

    guard let firstItem = viewModel.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    XCTAssertFalse(viewModel.isPerformingAction)
    await viewModel.toggleItem(firstItem)
    // isPerformingAction must remain false so buttons (e.g. Reset) don't flicker disabled/enabled
    XCTAssertFalse(viewModel.isPerformingAction)
  }

  func testResetAvailabilityRemainsStableWhileTogglingSubsequentItems() async {
    await viewModel.load()

    guard viewModel.items.count >= 2 else {
      XCTFail("At least 2 items expected")
      return
    }

    let item0 = viewModel.items[0]
    let item1 = viewModel.items[1]

    XCTAssertFalse(viewModel.canReset)

    await viewModel.toggleItem(item0)
    XCTAssertTrue(viewModel.canReset)
    XCTAssertFalse(viewModel.isPerformingAction)

    await viewModel.toggleItem(item1)
    XCTAssertTrue(viewModel.canReset)
    XCTAssertFalse(viewModel.isPerformingAction)

    await viewModel.toggleItem(item1)
    XCTAssertTrue(viewModel.canReset)
    XCTAssertFalse(viewModel.isPerformingAction)
  }

  // MARK: - Complete & Reset Tests

  func testCompleteRequiresAllItemsChecked() async {
    await viewModel.load()

    for item in viewModel.items {
      await viewModel.toggleItem(item)
    }

    XCTAssertTrue(viewModel.canComplete)
    await viewModel.complete()

    XCTAssertTrue(viewModel.isCompleted)
    XCTAssertFalse(viewModel.canComplete)
    XCTAssertTrue(viewModel.canReset)

    await viewModel.delete()
    XCTAssertNil(viewModel.session)
    XCTAssertTrue(viewModel.isSessionDeleted)
  }

  func testDeleteRemovesSession() async {
    await viewModel.load()

    guard let firstItem = viewModel.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    await viewModel.toggleItem(firstItem)
    XCTAssertEqual(viewModel.completedCount, 1)

    await viewModel.delete()
    XCTAssertNil(viewModel.session)
    XCTAssertTrue(viewModel.isSessionDeleted)
  }

  func testTemplateDeletionMarksSessionAsDeleted() async throws {
    await viewModel.load()
    XCTAssertNotNil(viewModel.session)
    XCTAssertFalse(viewModel.isSessionDeleted)

    let task = Task { [weak viewModel] in
      await viewModel?.observe()
    }
    defer { task.cancel() }

    try await checklistService.deleteTemplate(id: template.id)

    let start = Date()
    while !viewModel.isSessionDeleted && Date().timeIntervalSince(start) < 2.0 {
      try await Task.sleep(nanoseconds: 20_000_000)
    }

    XCTAssertTrue(viewModel.isSessionDeleted)
    XCTAssertNil(viewModel.session)
  }

  func testToggleItemIgnoredWhenSessionIsCompleted() async {
    await viewModel.load()

    for item in viewModel.items {
      await viewModel.toggleItem(item)
    }

    await viewModel.complete()
    XCTAssertTrue(viewModel.isCompleted)
    XCTAssertNil(viewModel.errorMessage)

    guard let firstItem = viewModel.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    // Tapping on an item when completed must be ignored: no state change, no error message
    await viewModel.toggleItem(firstItem)
    XCTAssertTrue(viewModel.isCompleted)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(viewModel.completedCount, 3)
    let rechecked = viewModel.items.first(where: { $0.id == firstItem.id })
    XCTAssertTrue(rechecked?.isChecked == true)
  }

  // MARK: - Category Support Tests

  func testLoadFetchesCategoryItem() async {
    await viewModel.load()

    XCTAssertNotNil(viewModel.categoryItem)
    XCTAssertEqual(viewModel.categoryId, ChecklistCategory.engineTechnical.rawValue)
    XCTAssertEqual(viewModel.categoryName, "Engine & Technical")
  }

  func testCategoryItemResolvesForCustomCategory() async throws {
    let customCategory = try await checklistService.createCategory(
      id: "custom_hull",
      name: "Hull & Keel",
      icon: "shield",
      sortOrder: 15
    )

    let customTemplate = try await checklistService.createCustomTemplate(
      title: "Hull Inspection",
      description: "Thru-hulls and zincs",
      category: .routine,
      categoryId: customCategory.id,
      items: [("Check seacocks", nil)]
    )

    let customSession = try await checklistService.startSession(templateId: customTemplate.id)

    let customVM = ChecklistSessionViewModel(
      sessionId: customSession.id,
      checklistService: checklistService
    )

    await customVM.load()

    XCTAssertEqual(customVM.categoryId, "custom_hull")
    XCTAssertEqual(customVM.categoryItem?.id, "custom_hull")
    XCTAssertEqual(customVM.categoryName, "Hull & Keel")
  }
}
