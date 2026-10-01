//
//  ChecklistTemplateDetailViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class ChecklistTemplateDetailViewModelTests: XCTestCase {
  private var databaseManager: DatabaseManager!
  private var checklistService: ChecklistService!
  private var template: ChecklistTemplate!
  private var viewModel: ChecklistTemplateDetailViewModel!

  override func setUp() async throws {
    try await super.setUp()
    databaseManager = try DatabaseManager.inMemory()
    checklistService = ChecklistService(
      databaseManager: databaseManager,
      throttler: ChecklistThrottler(window: .zero)
    )

    template = try await checklistService.createCustomTemplate(
      title: "Pre-Sail Brief",
      description: "Safety walkaround",
      category: .safetyEmergency,
      items: [
        (title: "Lifejackets", detail: "Count matches crew"),
        (title: "EPIRB check", detail: "Battery valid")
      ]
    )

    viewModel = ChecklistTemplateDetailViewModel(
      templateId: template.id,
      checklistService: checklistService
    )
  }

  override func tearDown() async throws {
    viewModel = nil
    template = nil
    checklistService = nil
    databaseManager = nil
    try await super.tearDown()
  }

  func testInitialState() {
    XCTAssertEqual(viewModel.templateId, template.id)
    XCTAssertNil(viewModel.template)
    XCTAssertNil(viewModel.activeSession)
    XCTAssertFalse(viewModel.isLoading)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(viewModel.title, "")
    XCTAssertNil(viewModel.description)
    XCTAssertNil(viewModel.category)
    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertFalse(viewModel.hasActiveSession)
  }

  func testLoadTemplate() async {
    await viewModel.load()

    XCTAssertNotNil(viewModel.template)
    XCTAssertEqual(viewModel.title, "Pre-Sail Brief")
    XCTAssertEqual(viewModel.description, "Safety walkaround")
    XCTAssertEqual(viewModel.category, .safetyEmergency)
    XCTAssertEqual(viewModel.items.count, 2)
    XCTAssertEqual(viewModel.items[0].title, "Lifejackets")
    XCTAssertEqual(viewModel.items[1].title, "EPIRB check")
    XCTAssertFalse(viewModel.hasActiveSession)
  }

  func testStartOrResumeSessionCreatesAndReturnsSessionId() async {
    await viewModel.load()

    let sessionId = await viewModel.startOrResumeSession()
    XCTAssertNotNil(sessionId)
    XCTAssertNotNil(viewModel.activeSession)
    XCTAssertEqual(viewModel.activeSession?.id, sessionId)
  }

  func testDeleteTemplate() async {
    await viewModel.load()

    let success = await viewModel.deleteTemplate()
    XCTAssertTrue(success)

    let reloaded = try? await checklistService.fetchTemplate(id: template.id)
    XCTAssertNil(reloaded)
  }
}
