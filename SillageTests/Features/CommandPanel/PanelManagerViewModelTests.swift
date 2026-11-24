//
//  PanelManagerViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class PanelManagerViewModelTests: XCTestCase {

  private var viewModel: PanelManagerViewModel!

  override func setUp() async throws {
    try await super.setUp()
    viewModel = PanelManagerViewModel()
  }

  override func tearDown() async throws {
    viewModel = nil
    try await super.tearDown()
  }

  // MARK: - Initial State

  func testInitialState() {
    XCTAssertEqual(viewModel.activePanel, .none)
    XCTAssertTrue(viewModel.commandPath.isEmpty)
  }

  // MARK: - Panel Open / Close / Toggle

  func testOpenPanel() {
    viewModel.openPanel(.command)
    XCTAssertEqual(viewModel.activePanel, .command)
  }

  func testClosePanelResetsPathAndDeactivates() {
    viewModel.openPanel(.command)
    viewModel.commandPath = [.settings, .chartPreferences, .geoGarageLogin(context: .initialSetup)]

    viewModel.closePanel()

    XCTAssertEqual(viewModel.activePanel, .none)
    XCTAssertTrue(viewModel.commandPath.isEmpty)
  }

  func testTogglePanel() {
    viewModel.togglePanel(.command)
    XCTAssertEqual(viewModel.activePanel, .command)

    viewModel.togglePanel(.command)
    XCTAssertEqual(viewModel.activePanel, .none)
  }

  func testSuspendPanelPreservesPathAcrossSheetDismissAndResume() {
    viewModel.openPanel(.command)
    let expectedPath: [PanelManagerViewModel.CommandDestination] = [.waypoints, .waypointDetail("wp_1")]
    viewModel.commandPath = expectedPath

    viewModel.suspendPanel()

    XCTAssertEqual(viewModel.activePanel, .none)
    XCTAssertEqual(viewModel.commandPath, expectedPath)

    // UIKit native sheet dismissal triggered by suspendPanel() must not clear the path
    viewModel.handleSheetDismissed()
    XCTAssertEqual(viewModel.commandPath, expectedPath)

    viewModel.resumePanel()
    XCTAssertEqual(viewModel.activePanel, .command)
    XCTAssertEqual(viewModel.commandPath, expectedPath)
  }

  func testHandleSheetDismissedDuringRotationPreservesPath() {
    viewModel.openPanel(.command)
    let expectedPath: [PanelManagerViewModel.CommandDestination] = [.settings, .chartPreferences]
    viewModel.commandPath = expectedPath

    // Rotation from Portrait sheet to Landscape drawer triggers sheet onDismiss while activePanel remains .command
    viewModel.handleSheetDismissed()

    XCTAssertEqual(viewModel.activePanel, .command)
    XCTAssertEqual(viewModel.commandPath, expectedPath)
  }

  func testHandleSheetDismissedAfterCloseClearsPath() {
    viewModel.openPanel(.command)
    viewModel.commandPath = [.settings, .chartPreferences]
    viewModel.activePanel = .none

    viewModel.handleSheetDismissed()
    XCTAssertTrue(viewModel.commandPath.isEmpty)

    // Idempotent on repeated dismissal callbacks
    viewModel.handleSheetDismissed()
    XCTAssertTrue(viewModel.commandPath.isEmpty)
  }

  func testOpenAnchorAlarmPanelAppendsDestination() {
    viewModel.openAnchorAlarmPanel()

    XCTAssertEqual(viewModel.activePanel, .command)
    XCTAssertEqual(viewModel.commandPath, [.anchorAlarm])

    // Re-calling should not duplicate the destination
    viewModel.openAnchorAlarmPanel()
    XCTAssertEqual(viewModel.commandPath, [.anchorAlarm])
  }

  func testOpenOfflineChartsPanelAppendsDestination() {
    viewModel.openOfflineChartsPanel()

    XCTAssertEqual(viewModel.activePanel, .command)
    XCTAssertEqual(viewModel.commandPath, [.offlineCharts])

    // Re-calling should not duplicate the destination
    viewModel.openOfflineChartsPanel()
    XCTAssertEqual(viewModel.commandPath, [.offlineCharts])
  }

  // MARK: - Intent Routing

  func testHandleIntentOpenSettingsGeoGarage() {
    viewModel.handle(intent: .openSettings(target: .geoGarage))
    XCTAssertEqual(viewModel.commandPath, [.geoGarageLogin(context: .reauthentication)])
  }

  func testHandleIntentOpenSettingsOther() {
    viewModel.handle(intent: .openSettings(target: .storage))
    XCTAssertEqual(viewModel.commandPath, [.settings])
  }

  func testHandleIntentNoneDoesNotModifyPath() {
    viewModel.handle(intent: .none)
    XCTAssertTrue(viewModel.commandPath.isEmpty)
  }

  // MARK: - CommandDestination Enum Hashing & Uniqueness

  func testCommandDestinationsUniqueness() {
    var destinations: [PanelManagerViewModel.CommandDestination] = [
      .settings,
      .tracks,
      .waypoints,
      .trackSessionDetail(sessionID: "session_123"),
      .waypointDetail("wp_1"),
      .baroAlarm,
      .anchorAlarm,
      .geoGarageLogin(context: .initialSetup),
      .offlineCharts,
      .offlineChartDetail(id: UUID()),
      .chartPreferences,
      .cogPreferences,
      .legalList,
      .legalDetail(.navigationWarning),
      .versionInfo,
      .modelsInfo,
      .checklists,
      .checklistCategories,
      .checklistCategoryDetail(ChecklistCategoryDetailPayload(categoryId: "safety_emergency")),
      .checklistTemplateDetail(ChecklistTemplateDetailPayload(templateId: UUID(), template: nil, startEditable: false)),
      .checklistSession(ChecklistSessionPayload(id: UUID()))
    ]
#if DEBUG
    destinations.append(.debugMenu)
    let expectedCount = 22
#else
    let expectedCount = 21
#endif

    let set = Set(destinations)
    XCTAssertEqual(set.count, destinations.count, "Each CommandDestination case must be uniquely hashable")
    XCTAssertEqual(destinations.count, expectedCount, "All CommandDestination enum cases must be tested for uniqueness")
  }

  func testChecklistCategoryDetailEqualityIgnoresCategoryObject() {
    let cat1 = ChecklistCategoryItem(id: "routine", name: "Routine 1")
    let cat2 = ChecklistCategoryItem(id: "routine", name: "Routine 2")
    let payload1 = ChecklistCategoryDetailPayload(categoryId: "routine", category: cat1)
    let payload2 = ChecklistCategoryDetailPayload(categoryId: "routine", category: cat2)
    let payload3 = ChecklistCategoryDetailPayload(categoryId: "routine", category: nil)
    XCTAssertEqual(payload1, payload2)
    XCTAssertEqual(payload1, payload3)
    XCTAssertEqual(payload1.hashValue, payload2.hashValue)
    XCTAssertEqual(payload1.hashValue, payload3.hashValue)

    let dest1 = PanelManagerViewModel.CommandDestination.checklistCategoryDetail(payload1)
    let dest2 = PanelManagerViewModel.CommandDestination.checklistCategoryDetail(payload2)
    XCTAssertEqual(dest1, dest2)
    XCTAssertEqual(dest1.hashValue, dest2.hashValue)
  }

  func testChecklistTemplateDetailEqualityIgnoresTemplateObject() {
    let id = UUID()
    let tpl1 = ChecklistTemplate(id: id, title: "T1", categoryId: "routine")
    let tpl2 = ChecklistTemplate(id: id, title: "T2", categoryId: "routine")
    let payload1 = ChecklistTemplateDetailPayload(templateId: id, template: tpl1, startEditable: false)
    let payload2 = ChecklistTemplateDetailPayload(templateId: id, template: tpl2, startEditable: false)
    XCTAssertEqual(payload1, payload2)
    XCTAssertEqual(payload1.hashValue, payload2.hashValue)

    let dest1 = PanelManagerViewModel.CommandDestination.checklistTemplateDetail(payload1)
    let dest2 = PanelManagerViewModel.CommandDestination.checklistTemplateDetail(payload2)
    XCTAssertEqual(dest1, dest2)
    XCTAssertEqual(dest1.hashValue, dest2.hashValue)
  }

  // MARK: - Navigation Path Stack Operations

  func testGeoGarageNavigationStackPath() {
    // Simulates navigating from Settings -> Chart Preferences -> GeoGarage Login
    viewModel.commandPath.append(.settings)
    viewModel.commandPath.append(.chartPreferences)
    viewModel.commandPath.append(.geoGarageLogin(context: .initialSetup))

    XCTAssertEqual(viewModel.commandPath.count, 3)
    XCTAssertEqual(viewModel.commandPath.last, .geoGarageLogin(context: .initialSetup))

    // Simulates popping back to Chart Preferences
    viewModel.commandPath.removeLast()
    XCTAssertEqual(viewModel.commandPath.last, .chartPreferences)

    // Simulates navigating to Offline Charts
    viewModel.commandPath.append(.offlineCharts)
    XCTAssertEqual(viewModel.commandPath.last, .offlineCharts)
  }
}
