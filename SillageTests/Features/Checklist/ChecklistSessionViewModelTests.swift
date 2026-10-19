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
  private var databaseManager: DatabaseManager?
  private var checklistService: ChecklistService?
  private var template: ChecklistTemplate?
  private var session: ChecklistSession?
  private var viewModel: ChecklistSessionViewModel?
  private var simulatedFix: NavigationFix?
  private var observeTask: Task<Void, Never>?
  private var isolatedDefaults: IsolatedUserDefaults?

  override func setUp() async throws {
    try await super.setUp()
    let isolated = IsolatedUserDefaults(prefix: "ChecklistSessionViewModelTests")
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
      title: "Engine Check",
      description: "Pre-departure engine inspection",
      categoryId: "engine_technical",
      items: [
        (title: "Check oil level", detail: "Dipstick between MIN and MAX"),
        (title: "Check raw water strainer", detail: "Free of weed and debris"),
        (title: "Visual belt check", detail: "Check tension and wear")
      ]
    )
    self.template = createdTemplate

    let createdSession = try await service.startSession(templateId: createdTemplate.id)
    self.session = createdSession

    self.viewModel = ChecklistSessionViewModel(
      sessionId: createdSession.id,
      checklistService: service,
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
    isolatedDefaults?.tearDown()
    isolatedDefaults = nil
    try await super.tearDown()
  }

  // MARK: - Load Tests

  func testInitWithPreloadedSessionExposesTitleInstantly() throws {
    let currentSession = try XCTUnwrap(session)
    let service = try XCTUnwrap(checklistService)

    let preloadedVM = ChecklistSessionViewModel(
      sessionId: currentSession.id,
      session: currentSession,
      checklistService: service
    )

    XCTAssertEqual(preloadedVM.title, "Engine Check")
    XCTAssertEqual(preloadedVM.items.count, 3)
    XCTAssertFalse(preloadedVM.title.isEmpty)
    XCTAssertNotNil(preloadedVM.session)
  }

  func testLoadFetchesSessionAndTemplate() async throws {
    let vm = try XCTUnwrap(viewModel)

    XCTAssertNil(vm.session)
    XCTAssertNil(vm.template)

    await vm.load()

    XCTAssertNotNil(vm.session)
    XCTAssertNotNil(vm.template)
    XCTAssertEqual(vm.title, "Engine Check")
    XCTAssertEqual(vm.description, "Pre-departure engine inspection")
    XCTAssertEqual(vm.categoryId, "engine_technical")
    XCTAssertEqual(vm.items.count, 3)
    XCTAssertEqual(vm.completedCount, 0)
    XCTAssertEqual(vm.totalCount, 3)
    XCTAssertEqual(vm.progressRatio, 0.0)
    XCTAssertFalse(vm.isCompleted)
    XCTAssertFalse(vm.canComplete)
    XCTAssertFalse(vm.canReset)
  }

  // MARK: - Toggle Item & GPS Audit Tests

  func testToggleItemWithAccurateLocationAuditing() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()

    simulatedFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 47.654, longitude: -3.123),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )

    guard let firstItem = vm.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    await vm.toggleItem(firstItem)

    XCTAssertEqual(vm.completedCount, 1)
    XCTAssertTrue(vm.canReset)
    XCTAssertFalse(vm.canComplete)

    let updatedItem = vm.items.first(where: { $0.id == firstItem.id })
    XCTAssertTrue(updatedItem?.isChecked == true)
    XCTAssertNotNil(updatedItem?.checkedAt)
    XCTAssertEqual(updatedItem?.coordinate?.latitude ?? 0, 47.654, accuracy: 0.0001)
    XCTAssertEqual(updatedItem?.coordinate?.longitude ?? 0, -3.123, accuracy: 0.0001)
  }

  func testToggleItemRejectsInaccurateGPSFix() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()

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

    guard let firstItem = vm.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    await vm.toggleItem(firstItem)

    let updatedItem = vm.items.first(where: { $0.id == firstItem.id })
    XCTAssertTrue(updatedItem?.isChecked == true)
    XCTAssertNil(updatedItem?.coordinate)
  }

  func testToggleItemDoesNotTriggerIsPerformingAction() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()

    guard let firstItem = vm.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    XCTAssertFalse(vm.isPerformingAction)
    await vm.toggleItem(firstItem)
    // isPerformingAction must remain false so buttons (e.g. Reset) don't flicker disabled/enabled
    XCTAssertFalse(vm.isPerformingAction)
  }

  func testResetAvailabilityRemainsStableWhileTogglingSubsequentItems() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()

    guard vm.items.count >= 2 else {
      XCTFail("At least 2 items expected")
      return
    }

    let item0 = vm.items[0]
    let item1 = vm.items[1]

    XCTAssertFalse(vm.canReset)

    await vm.toggleItem(item0)
    XCTAssertTrue(vm.canReset)
    XCTAssertFalse(vm.isPerformingAction)

    await vm.toggleItem(item1)
    XCTAssertTrue(vm.canReset)
    XCTAssertFalse(vm.isPerformingAction)

    await vm.toggleItem(item1)
    XCTAssertTrue(vm.canReset)
    XCTAssertFalse(vm.isPerformingAction)
  }

  // MARK: - Complete & Reset Tests

  func testCompleteRequiresAllItemsChecked() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()

    for item in vm.items {
      await vm.toggleItem(item)
    }

    XCTAssertTrue(vm.canComplete)
    await vm.complete()

    XCTAssertTrue(vm.isCompleted)
    XCTAssertFalse(vm.canComplete)
    XCTAssertTrue(vm.canReset)

    await vm.delete()
    XCTAssertNil(vm.session)
    XCTAssertTrue(vm.isSessionDeleted)
  }

  func testDeleteRemovesSession() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()

    guard let firstItem = vm.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    await vm.toggleItem(firstItem)
    XCTAssertEqual(vm.completedCount, 1)

    await vm.delete()
    XCTAssertNil(vm.session)
    XCTAssertTrue(vm.isSessionDeleted)
  }

  func testTemplateDeletionMarksSessionAsDeleted() async throws {
    let vm = try XCTUnwrap(viewModel)
    let service = try XCTUnwrap(checklistService)
    let currentTemplate = try XCTUnwrap(template)

    await vm.load()
    XCTAssertNotNil(vm.session)
    XCTAssertFalse(vm.isSessionDeleted)

    let task = Task { [weak vm] in
      await vm?.observe()
    }
    defer { task.cancel() }

    try await service.deleteTemplate(id: currentTemplate.id)

    let start = Date()
    while !vm.isSessionDeleted && Date().timeIntervalSince(start) < 2.0 {
      try await Task.sleep(nanoseconds: 20_000_000)
    }

    XCTAssertTrue(vm.isSessionDeleted)
    XCTAssertNil(vm.session)
  }

  func testToggleItemIgnoredWhenSessionIsCompleted() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()

    for item in vm.items {
      await vm.toggleItem(item)
    }

    await vm.complete()
    XCTAssertTrue(vm.isCompleted)
    XCTAssertNil(vm.errorMessage)

    guard let firstItem = vm.items.first else {
      XCTFail("Items should not be empty")
      return
    }

    // Tapping on an item when completed must be ignored: no state change, no error message
    await vm.toggleItem(firstItem)
    XCTAssertTrue(vm.isCompleted)
    XCTAssertNil(vm.errorMessage)
    XCTAssertEqual(vm.completedCount, 3)
    let rechecked = vm.items.first(where: { $0.id == firstItem.id })
    XCTAssertTrue(rechecked?.isChecked == true)
  }

  // MARK: - Category Support Tests

  func testLoadFetchesCategoryItem() async throws {
    let vm = try XCTUnwrap(viewModel)
    await vm.load()

    XCTAssertNotNil(vm.categoryItem)
    XCTAssertEqual(vm.categoryId, "engine_technical")
    XCTAssertEqual(vm.categoryName, vm.categoryItem?.name)
    XCTAssertFalse(vm.categoryName.isEmpty)
  }

  func testCategoryItemResolvesForCustomCategory() async throws {
    let service = try XCTUnwrap(checklistService)
    let customCategory = try await service.createCategory(
      id: "custom_hull",
      name: "Hull & Keel",
      icon: "shield",
      sortOrder: 15
    )

    let customTemplate = try await service.createCustomTemplate(
      title: "Hull Inspection",
      description: "Thru-hulls and zincs",
      categoryId: customCategory.id,
      items: [("Check seacocks", nil)]
    )

    let customSession = try await service.startSession(templateId: customTemplate.id)

    let customVM = ChecklistSessionViewModel(
      sessionId: customSession.id,
      checklistService: service
    )

    await customVM.load()

    XCTAssertEqual(customVM.categoryId, "custom_hull")
    XCTAssertEqual(customVM.categoryItem?.id, "custom_hull")
    XCTAssertEqual(customVM.categoryName, "Hull & Keel")
  }
}
