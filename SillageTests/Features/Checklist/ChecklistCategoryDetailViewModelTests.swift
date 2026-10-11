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
import CoreLocation
@testable import Sillage

@MainActor
final class ChecklistCategoryDetailViewModelTests: XCTestCase {
  private var mockService: MockChecklistService!
  private var viewModel: ChecklistCategoryDetailViewModel!

  override func setUp() async throws {
    try await super.setUp()
    mockService = MockChecklistService()
    viewModel = ChecklistCategoryDetailViewModel(
      categoryId: "safety_emergency",
      checklistService: mockService
    )
  }

  override func tearDown() async throws {
    viewModel = nil
    mockService = nil
    try await super.tearDown()
  }

  // MARK: - Initial State

  func testInitialState() {
    XCTAssertEqual(viewModel.categoryId, "safety_emergency")
    XCTAssertNil(viewModel.category)
    XCTAssertTrue(viewModel.associatedTemplates.isEmpty)
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertTrue(viewModel.isBuiltIn)
    XCTAssertEqual(viewModel.name, "")
    XCTAssertNil(viewModel.icon)
    XCTAssertEqual(viewModel.displaySystemImage, "checklist")
    XCTAssertEqual(viewModel.sortOrder, 0)
  }

  func testInitialStateWithPrepopulatedCategory() {
    let sample = ChecklistCategoryItem(
      id: "safety_emergency",
      name: "Safety & Emergency",
      icon: "exclamationmark.shield.fill",
      sortOrder: 2
    )
    let prepopulatedVM = ChecklistCategoryDetailViewModel(
      categoryId: "safety_emergency",
      category: sample,
      checklistService: mockService
    )

    XCTAssertEqual(prepopulatedVM.category?.id, "safety_emergency")
    XCTAssertEqual(prepopulatedVM.name, "Safety & Emergency")
    XCTAssertEqual(prepopulatedVM.icon, "exclamationmark.shield.fill")
    XCTAssertEqual(prepopulatedVM.sortOrder, 2)
  }

  // MARK: - Successful Loading

  func testLoadCategorySuccess() async {
    let sampleCategory = ChecklistCategoryItem(
      id: "safety_emergency",
      name: "Safety & Emergency",
      icon: "exclamationmark.shield.fill",
      sortOrder: 0
    )
    mockService.categoryToReturn = sampleCategory

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
    mockService.templatesToReturn = [matchingTemplate1, otherTemplate, matchingTemplate0]

    await viewModel.loadCategory()

    XCTAssertEqual(viewModel.category?.id, "safety_emergency")
    XCTAssertEqual(viewModel.name, "Safety & Emergency")
    XCTAssertEqual(viewModel.icon, "exclamationmark.shield.fill")
    XCTAssertEqual(viewModel.displaySystemImage, "exclamationmark.shield.fill")
    XCTAssertEqual(viewModel.associatedTemplates.count, 2)
    // Check sorting
    XCTAssertEqual(viewModel.associatedTemplates.first?.title, "Abandon Ship")
    XCTAssertEqual(viewModel.associatedTemplates.last?.title, "Engine Failure")
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNil(viewModel.errorMessage)
  }

  // MARK: - Custom Category Detection

  func testCustomCategoryIsNotBuiltIn() {
    let customViewModel = ChecklistCategoryDetailViewModel(
      categoryId: "custom_sails",
      checklistService: mockService
    )
    XCTAssertFalse(customViewModel.isBuiltIn)
  }

  // MARK: - Error Handling

  func testLoadCategoryFailureSetsErrorMessage() async {
    mockService.errorToThrow = NSError(domain: "test", code: -1, userInfo: nil)

    await viewModel.loadCategory()

    XCTAssertNil(viewModel.category)
    XCTAssertTrue(viewModel.associatedTemplates.isEmpty)
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNotNil(viewModel.errorMessage)
  }

  func testLoadCategoryCancellationDoesNotSetErrorMessage() async {
    mockService.errorToThrow = CancellationError()

    await viewModel.loadCategory()

    XCTAssertNil(viewModel.category)
    XCTAssertTrue(viewModel.associatedTemplates.isEmpty)
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNil(viewModel.errorMessage)
  }
}

// MARK: - Test Mock

@MainActor
private final class MockChecklistService: ChecklistServiceProtocol {
  var categoryToReturn: ChecklistCategoryItem?
  var templatesToReturn: [ChecklistTemplate] = []
  var errorToThrow: (any Error)?

  func fetchCategories() async throws -> [ChecklistCategoryItem] { [] }

  func fetchCategory(id: String) async throws -> ChecklistCategoryItem? {
    if let error = errorToThrow {
      throw error
    }
    return categoryToReturn
  }

  func createCategory(id: String?, name: String, icon: String?, sortOrder: Int?) async throws -> ChecklistCategoryItem {
    fatalError("Unused in ViewModel tests")
  }
  func updateCategory(id: String, name: String, icon: String?, sortOrder: Int?) async throws -> ChecklistCategoryItem {
    fatalError("Unused in ViewModel tests")
  }
  func deleteCategory(id: String) async throws {}
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
    fatalError("Unused")
  }
  func updateTemplate(id: UUID, title: String, description: String?, categoryId: String, items: [(id: UUID?, title: String, detail: String?)]) async throws -> ChecklistTemplate {
    fatalError("Unused")
  }
  func deleteTemplate(id: UUID) async throws {}
  func createCustomTemplate(title: String, description: String?, categoryId: String, items: [(title: String, detail: String?)]) async throws -> ChecklistTemplate {
    fatalError("Unused")
  }
  func updateCustomTemplate(id: UUID, title: String, description: String?, categoryId: String, items: [(id: UUID?, title: String, detail: String?)]) async throws -> ChecklistTemplate {
    fatalError("Unused")
  }
  func deleteCustomTemplate(id: UUID) async throws {}

  func startSession(templateId: UUID) async throws(ChecklistSessionError) -> ChecklistSession {
    fatalError("Unused")
  }
  func fetchActiveSession(for templateId: UUID) async throws -> ChecklistSession? { nil }
  func fetchSession(id: UUID) async throws -> ChecklistSession? { nil }
  func fetchRecentSessions(limit: Int) async throws -> [ChecklistSession] { [] }
  func setItemChecked(sessionId: UUID, itemId: UUID, isChecked: Bool, coordinate: CLLocationCoordinate2D?) async throws(ChecklistSessionError) -> ChecklistSession {
    fatalError("Unused")
  }
  func deleteSession(sessionId: UUID) async throws(ChecklistSessionError) {}
  func completeSession(sessionId: UUID, notes: String?) async throws(ChecklistSessionError) -> ChecklistSession {
    fatalError("Unused")
  }
  func abandonSession(sessionId: UUID) async throws(ChecklistSessionError) -> ChecklistSession {
    fatalError("Unused")
  }
  func seedDefaultTemplatesIfNeeded() async throws {}
  func fetchLatestCompletionDate(for templateId: UUID) async throws -> Date? { nil }

  func observeSessions() -> AsyncThrowingStream<[ChecklistSession], any Error> {
    AsyncThrowingStream { $0.finish() }
  }
  func observeActiveSessions() -> AsyncThrowingStream<[ChecklistSession], any Error> {
    AsyncThrowingStream { $0.finish() }
  }
  func observeCompletedSessions() -> AsyncThrowingStream<[UUID: Date], any Error> {
    AsyncThrowingStream { $0.finish() }
  }
}
