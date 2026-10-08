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
import CoreLocation
@testable import Sillage

@MainActor
final class ChecklistCategoryListViewModelTests: XCTestCase {
  private var mockService: MockChecklistService!
  private var viewModel: ChecklistCategoryListViewModel!

  override func setUp() async throws {
    try await super.setUp()
    mockService = MockChecklistService()
    viewModel = ChecklistCategoryListViewModel(checklistService: mockService)
  }

  override func tearDown() async throws {
    viewModel = nil
    mockService = nil
    try await super.tearDown()
  }

  // MARK: - Initial State

  func testInitialState() {
    XCTAssertTrue(viewModel.categories.isEmpty)
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNil(viewModel.errorMessage)
  }

  // MARK: - Successful Loading

  func testLoadCategoriesSuccess() async {
    let sampleCategories = [
      ChecklistCategoryItem(id: "routine", name: "Routine", icon: "checklist", sortOrder: 0),
      ChecklistCategoryItem(id: "emergency", name: "Emergency", icon: "exclamationmark.triangle", sortOrder: 1)
    ]
    mockService.categoriesToReturn = sampleCategories

    await viewModel.loadCategories()

    XCTAssertEqual(viewModel.categories.count, 2)
    XCTAssertEqual(viewModel.categories.first?.id, "routine")
    XCTAssertEqual(viewModel.categories.last?.id, "emergency")
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNil(viewModel.errorMessage)
  }

  func testLoadCategoriesFailureSetsErrorMessage() async {
    mockService.errorToThrow = NSError(domain: "test", code: -1, userInfo: nil)

    await viewModel.loadCategories()

    XCTAssertTrue(viewModel.categories.isEmpty)
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNotNil(viewModel.errorMessage)
  }

  func testLoadCategoriesCancellationDoesNotSetErrorMessage() async {
    mockService.errorToThrow = CancellationError()

    await viewModel.loadCategories()

    XCTAssertTrue(viewModel.categories.isEmpty)
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNil(viewModel.errorMessage)
  }
}

// MARK: - Test Mock

@MainActor
private final class MockChecklistService: ChecklistServiceProtocol {
  var categoriesToReturn: [ChecklistCategoryItem] = []
  var errorToThrow: (any Error)?

  func fetchCategories() async throws -> [ChecklistCategoryItem] {
    if let error = errorToThrow {
      throw error
    }
    return categoriesToReturn
  }

  func fetchCategory(id: String) async throws -> ChecklistCategoryItem? { nil }
  func createCategory(id: String?, name: String, icon: String?, sortOrder: Int?) async throws -> ChecklistCategoryItem {
    fatalError("Unused in ViewModel tests")
  }
  func updateCategory(id: String, name: String, icon: String?, sortOrder: Int?) async throws -> ChecklistCategoryItem {
    fatalError("Unused in ViewModel tests")
  }
  func deleteCategory(id: String) async throws {}

  func fetchTemplates() async throws -> [ChecklistTemplate] { [] }
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
