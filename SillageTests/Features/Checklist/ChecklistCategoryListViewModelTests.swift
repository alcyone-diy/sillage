//
//  ChecklistCategoryListViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class ChecklistCategoryListViewModelTests: XCTestCase {
  private var mockService: MockChecklistCatalogService?
  private var viewModel: ChecklistCategoryListViewModel?

  override func setUp() async throws {
    try await super.setUp()
    let mock = MockChecklistCatalogService()
    mockService = mock
    viewModel = ChecklistCategoryListViewModel(catalogService: mock)
  }

  override func tearDown() async throws {
    viewModel = nil
    mockService = nil
    try await super.tearDown()
  }

  // MARK: - Initial State

  func testInitialState() throws {
    let vm = try XCTUnwrap(viewModel)
    XCTAssertTrue(vm.categories.isEmpty)
    XCTAssertFalse(vm.isLoading)
    XCTAssertNil(vm.errorMessage)
  }

  // MARK: - Successful Loading

  func testLoadCategoriesSuccess() async throws {
    let mock = try XCTUnwrap(mockService)
    let vm = try XCTUnwrap(viewModel)
    let sampleCategories = [
      ChecklistCategoryItem(id: "routine", name: "Routine", icon: "checklist", sortOrder: 0),
      ChecklistCategoryItem(id: "emergency", name: "Emergency", icon: "exclamationmark.triangle", sortOrder: 1)
    ]
    mock.categoriesToReturn = sampleCategories

    await vm.loadCategories()

    XCTAssertEqual(vm.categories.count, 2)
    XCTAssertEqual(vm.categories.first?.id, "routine")
    XCTAssertEqual(vm.categories.last?.id, "emergency")
    XCTAssertFalse(vm.isLoading)
    XCTAssertNil(vm.errorMessage)
  }

  func testLoadCategoriesSuccessWithChecklistCounts() async throws {
    let mock = try XCTUnwrap(mockService)
    let vm = try XCTUnwrap(viewModel)
    let sampleCategories = [
      ChecklistCategoryItem(id: "routine", name: "Routine", icon: "checklist", sortOrder: 0),
      ChecklistCategoryItem(id: "emergency", name: "Emergency", icon: "exclamationmark.triangle", sortOrder: 1),
      ChecklistCategoryItem(id: "engine", name: "Engine", icon: "wrench", sortOrder: 2)
    ]
    mock.categoriesToReturn = sampleCategories
    mock.countsToReturn = [
      "routine": 2,
      "emergency": 1
    ]

    await vm.loadCategories()

    XCTAssertEqual(vm.categories.count, 3)
    XCTAssertEqual(vm.checklistCount(for: "routine"), 2)
    XCTAssertEqual(vm.checklistCount(for: "emergency"), 1)
    XCTAssertEqual(vm.checklistCount(for: "engine"), 0)
    XCTAssertEqual(vm.checklistCount(for: "nonexistent"), 0)
    XCTAssertFalse(vm.isLoading)
    XCTAssertNil(vm.errorMessage)
  }

  func testLoadCategoriesFailureSetsErrorMessage() async throws {
    let mock = try XCTUnwrap(mockService)
    let vm = try XCTUnwrap(viewModel)
    mock.errorToThrow = NSError(domain: "test", code: -1, userInfo: nil)

    await vm.loadCategories()

    XCTAssertTrue(vm.categories.isEmpty)
    XCTAssertFalse(vm.isLoading)
    XCTAssertNotNil(vm.errorMessage)
  }

  func testLoadCategoriesCancellationDoesNotSetErrorMessage() async throws {
    let mock = try XCTUnwrap(mockService)
    let vm = try XCTUnwrap(viewModel)
    mock.errorToThrow = CancellationError()

    await vm.loadCategories()

    XCTAssertTrue(vm.categories.isEmpty)
    XCTAssertFalse(vm.isLoading)
    XCTAssertNil(vm.errorMessage)
  }

  // MARK: - Reordering

  func testMoveCategoriesUpdatesOrderAndPersists() async throws {
    let mock = try XCTUnwrap(mockService)
    let vm = try XCTUnwrap(viewModel)
    mock.categoriesToReturn = [
      ChecklistCategoryItem(id: "cat_a", name: "Alpha", sortOrder: 0),
      ChecklistCategoryItem(id: "cat_b", name: "Bravo", sortOrder: 1),
      ChecklistCategoryItem(id: "cat_c", name: "Charlie", sortOrder: 2)
    ]
    await vm.loadCategories()

    // Move first category to the end
    vm.moveCategories(fromOffsets: IndexSet(integer: 0), toOffset: 3)
    await Task.yield()

    XCTAssertEqual(vm.categories.map(\.id), ["cat_b", "cat_c", "cat_a"])
    XCTAssertEqual(vm.categories.map(\.sortOrder), [0, 1, 2])
    XCTAssertEqual(mock.reorderCallCount, 1)
    XCTAssertEqual(mock.lastReorderedIds, ["cat_b", "cat_c", "cat_a"])
  }

  func testMoveCategoryUpAndDown() async throws {
    let mock = try XCTUnwrap(mockService)
    let vm = try XCTUnwrap(viewModel)
    mock.categoriesToReturn = [
      ChecklistCategoryItem(id: "cat_a", name: "Alpha", sortOrder: 0),
      ChecklistCategoryItem(id: "cat_b", name: "Bravo", sortOrder: 1),
      ChecklistCategoryItem(id: "cat_c", name: "Charlie", sortOrder: 2)
    ]
    await vm.loadCategories()

    vm.moveCategoryUp(id: "cat_b")
    await Task.yield()
    XCTAssertEqual(vm.categories.map(\.id), ["cat_b", "cat_a", "cat_c"])
    XCTAssertEqual(vm.categories.map(\.sortOrder), [0, 1, 2])
    XCTAssertEqual(mock.reorderCallCount, 1)
    XCTAssertEqual(mock.lastReorderedIds, ["cat_b", "cat_a", "cat_c"])

    vm.moveCategoryDown(id: "cat_b")
    await Task.yield()
    XCTAssertEqual(vm.categories.map(\.id), ["cat_a", "cat_b", "cat_c"])
    XCTAssertEqual(vm.categories.map(\.sortOrder), [0, 1, 2])
    XCTAssertEqual(mock.reorderCallCount, 2)
    XCTAssertEqual(mock.lastReorderedIds, ["cat_a", "cat_b", "cat_c"])
  }

  func testRapidConsecutiveMovesCancelsPreviousSaveTasksAndPersistsOnlyOnce() async throws {
    let mock = try XCTUnwrap(mockService)
    let vm = try XCTUnwrap(viewModel)
    mock.categoriesToReturn = [
      ChecklistCategoryItem(id: "cat_a", name: "Alpha", sortOrder: 0),
      ChecklistCategoryItem(id: "cat_b", name: "Bravo", sortOrder: 1),
      ChecklistCategoryItem(id: "cat_c", name: "Charlie", sortOrder: 2)
    ]
    await vm.loadCategories()

    // Synchronously trigger multiple consecutive moves before yielding the MainActor
    vm.moveCategoryUp(id: "cat_c")   // -> [cat_a, cat_c, cat_b]
    vm.moveCategoryUp(id: "cat_c")   // -> [cat_c, cat_a, cat_b]
    vm.moveCategoryDown(id: "cat_a") // -> [cat_c, cat_b, cat_a]

    await Task.yield()

    XCTAssertEqual(vm.categories.map(\.id), ["cat_c", "cat_b", "cat_a"])
    XCTAssertEqual(vm.categories.map(\.sortOrder), [0, 1, 2])
    XCTAssertEqual(mock.reorderCallCount, 1)
    XCTAssertEqual(mock.lastReorderedIds, ["cat_c", "cat_b", "cat_a"])
  }
}

// MARK: - Test Mock

@MainActor
private final class MockChecklistCatalogService: ChecklistCatalogServiceProtocol {
  var categoriesToReturn: [ChecklistCategoryItem] = []
  var countsToReturn: [String: Int] = [:]
  var templatesToReturn: [ChecklistTemplate] = []
  var reorderCallCount: Int = 0
  var lastReorderedIds: [String]?
  var errorToThrow: (any Error)?

  func fetchCategories() async throws -> [ChecklistCategoryItem] {
    if let error = errorToThrow {
      throw error
    }
    return categoriesToReturn
  }

  func fetchCategory(id: String) async throws -> ChecklistCategoryItem? { nil }
  func createCategory(id: String?, name: String, icon: String?, sortOrder: Int?) async throws -> ChecklistCategoryItem {
    throw ChecklistError.databaseFailure("Unused in ViewModel tests")
  }
  func updateCategory(id: String, name: String, icon: String?, sortOrder: Int?) async throws -> ChecklistCategoryItem {
    throw ChecklistError.databaseFailure("Unused in ViewModel tests")
  }
  func deleteCategory(id: String) async throws {}
  func reorderCategories(ids: [String]) async throws {
    if let error = errorToThrow {
      throw error
    }
    reorderCallCount += 1
    lastReorderedIds = ids
  }

  func fetchChecklistCountsByCategory() async throws -> [String: Int] {
    if let error = errorToThrow {
      throw error
    }
    return countsToReturn
  }

  func fetchTemplates() async throws -> [ChecklistTemplate] {
    if let error = errorToThrow {
      throw error
    }
    return templatesToReturn
  }
  func fetchTemplate(id: UUID) async throws -> ChecklistTemplate? { nil }
  func createTemplate(title: String, description: String?, categoryId: String, items: [(title: String, detail: String?)]) async throws -> ChecklistTemplate {
    throw ChecklistError.databaseFailure("Unused in ViewModel tests")
  }
  func updateTemplate(id: UUID, title: String, description: String?, categoryId: String, items: [(id: UUID?, title: String, detail: String?)]) async throws -> ChecklistTemplate {
    throw ChecklistError.databaseFailure("Unused in ViewModel tests")
  }
  func deleteTemplate(id: UUID) async throws {}
  func seedDefaultTemplatesIfNeeded() async throws {}
}
