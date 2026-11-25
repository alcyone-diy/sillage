//
//  ChecklistCategoryDetailViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-10.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class ChecklistCategoryDetailViewModelTests: XCTestCase {
  private var mockService: MockChecklistCatalogService?
  private var viewModel: ChecklistCategoryDetailViewModel?

  override func setUp() async throws {
    try await super.setUp()
    let mock = MockChecklistCatalogService()
    mockService = mock
    viewModel = ChecklistCategoryDetailViewModel(
      categoryId: "safety_emergency",
      catalogService: mock
    )
  }

  override func tearDown() async throws {
    viewModel = nil
    mockService = nil
    try await super.tearDown()
  }

  // MARK: - Initial State

  func testInitialState() throws {
    let vm = try XCTUnwrap(viewModel)
    XCTAssertEqual(vm.categoryId, "safety_emergency")
    XCTAssertNil(vm.category)
    XCTAssertTrue(vm.associatedTemplates.isEmpty)
    XCTAssertFalse(vm.isLoading)
    XCTAssertNil(vm.errorMessage)
    XCTAssertEqual(vm.name, "")
    XCTAssertNil(vm.icon)
    XCTAssertEqual(vm.displaySystemImage, "checklist")
    XCTAssertEqual(vm.sortOrder, 0)
  }

  func testInitialStateWithPrepopulatedCategory() throws {
    let mock = try XCTUnwrap(mockService)
    let sample = ChecklistCategoryItem(
      id: "safety_emergency",
      name: "Safety & Emergency",
      icon: "exclamationmark.shield.fill",
      sortOrder: 2
    )
    let prepopulatedVM = ChecklistCategoryDetailViewModel(
      categoryId: "safety_emergency",
      category: sample,
      catalogService: mock
    )

    XCTAssertEqual(prepopulatedVM.category?.id, "safety_emergency")
    XCTAssertEqual(prepopulatedVM.name, "Safety & Emergency")
    XCTAssertEqual(prepopulatedVM.icon, "exclamationmark.shield.fill")
    XCTAssertEqual(prepopulatedVM.sortOrder, 2)
  }

  // MARK: - Successful Loading

  func testLoadCategorySuccess() async throws {
    let mock = try XCTUnwrap(mockService)
    let vm = try XCTUnwrap(viewModel)
    let sampleCategory = ChecklistCategoryItem(
      id: "safety_emergency",
      name: "Safety & Emergency",
      icon: "exclamationmark.shield.fill",
      sortOrder: 0
    )
    mock.categoryToReturn = sampleCategory

    let matchingTemplate1 = ChecklistTemplate(
      id: UUID(),
      title: "Engine Failure",
      description: "Immediate actions",
      categoryId: "safety_emergency",
      sortOrder: 1
    )
    let matchingTemplate0 = ChecklistTemplate(
      id: UUID(),
      title: "Abandon Ship",
      description: "Emergency distress",
      categoryId: "safety_emergency",
      sortOrder: 0
    )
    let otherTemplate = ChecklistTemplate(
      id: UUID(),
      title: "Pre-Departure",
      categoryId: "routine",
      sortOrder: 0
    )
    mock.templatesToReturn = [matchingTemplate1, otherTemplate, matchingTemplate0]

    await vm.loadCategory()

    XCTAssertEqual(vm.category?.id, "safety_emergency")
    XCTAssertEqual(vm.name, "Safety & Emergency")
    XCTAssertEqual(vm.icon, "exclamationmark.shield.fill")
    XCTAssertEqual(vm.displaySystemImage, "exclamationmark.shield.fill")
    XCTAssertEqual(vm.associatedTemplates.count, 2)
    XCTAssertEqual(vm.associatedTemplates.first?.title, "Abandon Ship")
    XCTAssertEqual(vm.associatedTemplates.last?.title, "Engine Failure")
    XCTAssertFalse(vm.isLoading)
    XCTAssertNil(vm.errorMessage)
  }

  // MARK: - Deletion Eligibility

  func testAnyCategoryWithoutTemplatesCanBeDeleted() throws {
    let mock = try XCTUnwrap(mockService)
    let safetyVM = ChecklistCategoryDetailViewModel(
      categoryId: "safety_emergency",
      catalogService: mock
    )
    XCTAssertTrue(safetyVM.canDelete)
  }

  // MARK: - Error Handling

  func testLoadCategoryFailureSetsErrorMessage() async throws {
    let mock = try XCTUnwrap(mockService)
    let vm = try XCTUnwrap(viewModel)
    mock.errorToThrow = NSError(domain: "test", code: -1, userInfo: nil)

    await vm.loadCategory()

    XCTAssertNil(vm.category)
    XCTAssertTrue(vm.associatedTemplates.isEmpty)
    XCTAssertFalse(vm.isLoading)
    XCTAssertNotNil(vm.errorMessage)
  }

  func testLoadCategoryCancellationDoesNotSetErrorMessage() async throws {
    let mock = try XCTUnwrap(mockService)
    let vm = try XCTUnwrap(viewModel)
    mock.errorToThrow = CancellationError()

    await vm.loadCategory()

    XCTAssertNil(vm.category)
    XCTAssertTrue(vm.associatedTemplates.isEmpty)
    XCTAssertFalse(vm.isLoading)
    XCTAssertNil(vm.errorMessage)
  }

  // MARK: - Editing, Creation & Deletion

  func testEditAndSaveCategoryUpdatesCategoryAndExitsEditMode() async throws {
    let mock = try XCTUnwrap(mockService)
    let vm = try XCTUnwrap(viewModel)
    let initial = ChecklistCategoryItem(
      id: "safety_emergency",
      name: "Safety & Emergency",
      icon: "exclamationmark.shield.fill",
      sortOrder: 0
    )
    mock.categoryToReturn = initial
    await vm.loadCategory()

    vm.isEditable = true
    vm.name = "  Safety & Rescue  "
    vm.icon = "lifepreserver.fill"

    let saved = await vm.save()
    XCTAssertNotNil(saved)
    XCTAssertFalse(vm.isEditable)
    XCTAssertEqual(vm.name, "Safety & Rescue")
    XCTAssertEqual(vm.icon, "lifepreserver.fill")
    XCTAssertEqual(vm.displaySystemImage, "lifepreserver.fill")
  }

  func testCreateNewCategorySavesAndSetsCategoryId() async throws {
    let mock = try XCTUnwrap(mockService)
    let creationVM = ChecklistCategoryDetailViewModel(
      categoryId: nil,
      catalogService: mock,
      startEditable: true
    )
    XCTAssertNil(creationVM.categoryId)
    XCTAssertTrue(creationVM.isNew)
    XCTAssertTrue(creationVM.isEditable)
    XCTAssertFalse(creationVM.isValid)
    XCTAssertEqual(creationVM.availableIcons, MarineTheme.Icons.checklistCategoryDefaults)

    creationVM.name = "Rigging & Sails"
    creationVM.icon = "sailboat.fill"
    XCTAssertTrue(creationVM.isValid)

    let saved = await creationVM.save()
    XCTAssertNotNil(saved)
    XCTAssertFalse(creationVM.isNew)
    XCTAssertFalse(creationVM.isEditable)
    XCTAssertEqual(creationVM.name, "Rigging & Sails")
    XCTAssertEqual(creationVM.icon, "sailboat.fill")
    XCTAssertNotNil(creationVM.categoryId)
    XCTAssertEqual(creationVM.categoryId, saved?.id)
  }

  func testRevertRestoresOriginalValues() throws {
    let mock = try XCTUnwrap(mockService)
    let initial = ChecklistCategoryItem(
      id: "routine",
      name: "Routine",
      icon: "checklist",
      sortOrder: 2
    )
    let vm = ChecklistCategoryDetailViewModel(
      categoryId: "routine",
      category: initial,
      catalogService: mock,
      startEditable: true
    )

    vm.name = "Modified Name"
    vm.icon = "wind"
    vm.revert()

    XCTAssertFalse(vm.isEditable)
    XCTAssertEqual(vm.name, "Routine")
    XCTAssertEqual(vm.icon, "checklist")
  }

  func testCanDeleteAndDeleteCustomCategory() async throws {
    let mock = try XCTUnwrap(mockService)
    let custom = ChecklistCategoryItem(
      id: "custom_sails",
      name: "Sails",
      icon: "sailboat.fill",
      sortOrder: 5
    )
    mock.categoryToReturn = custom
    let customVM = ChecklistCategoryDetailViewModel(
      categoryId: "custom_sails",
      category: custom,
      catalogService: mock
    )
    await customVM.loadCategory()

    XCTAssertTrue(customVM.canDelete)
    let deleted = await customVM.deleteCategory()
    XCTAssertTrue(deleted)
    XCTAssertEqual(mock.deletedCategoryId, "custom_sails")
  }
}

// MARK: - Test Mock

@MainActor
private final class MockChecklistCatalogService: ChecklistCatalogServiceProtocol {
  var categoryToReturn: ChecklistCategoryItem?
  var templatesToReturn: [ChecklistTemplate] = []
  var deletedCategoryId: String?
  var errorToThrow: (any Error)?

  func fetchCategories() async throws -> [ChecklistCategoryItem] { [] }

  func fetchCategory(id: String) async throws -> ChecklistCategoryItem? {
    if let error = errorToThrow {
      throw error
    }
    return categoryToReturn
  }

  func createCategory(id: String?, name: String, icon: String?, sortOrder: Int?) async throws -> ChecklistCategoryItem {
    if let error = errorToThrow {
      throw error
    }
    return ChecklistCategoryItem(
      id: id ?? UUID().uuidString,
      name: name,
      icon: icon,
      sortOrder: sortOrder ?? 0
    )
  }

  func updateCategory(id: String, name: String, icon: String?, sortOrder: Int?) async throws -> ChecklistCategoryItem {
    if let error = errorToThrow {
      throw error
    }
    return ChecklistCategoryItem(
      id: id,
      name: name,
      icon: icon,
      sortOrder: sortOrder ?? 0
    )
  }

  func deleteCategory(id: String) async throws {
    if let error = errorToThrow {
      throw error
    }
    deletedCategoryId = id
  }
  func reorderCategories(ids: [String]) async throws {}
  func fetchChecklistCountsByCategory() async throws -> [String: Int] { [:] }

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
