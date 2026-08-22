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

  override func setUp() {
    super.setUp()
    viewModel = PanelManagerViewModel()
  }

  override func tearDown() {
    viewModel = nil
    super.tearDown()
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
    viewModel.commandPath = [.settings, .chartPreferences, .geoGarageLogin]

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
    XCTAssertEqual(viewModel.commandPath, [.geoGarageLogin])
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
    let destinations: [PanelManagerViewModel.CommandDestination] = [
      .settings,
      .tracks,
      .waypoints,
      .sessionDetail(sessionID: "session_123"),
      .waypointDetail("wp_1"),
      .baroAlarm,
      .anchorAlarm,
      .geoGarageLogin,
      .offlineCharts,
      .offlineChartDetail(id: UUID()),
      .chartPreferences
    ]

    let set = Set(destinations)
    XCTAssertEqual(set.count, destinations.count, "Each CommandDestination case must be uniquely hashable")
  }

  // MARK: - Navigation Path Stack Operations

  func testGeoGarageNavigationStackPath() {
    // Simulates navigating from Settings -> Chart Preferences -> GeoGarage Login
    viewModel.commandPath.append(.settings)
    viewModel.commandPath.append(.chartPreferences)
    viewModel.commandPath.append(.geoGarageLogin)

    XCTAssertEqual(viewModel.commandPath.count, 3)
    XCTAssertEqual(viewModel.commandPath.last, .geoGarageLogin)

    // Simulates popping back to Chart Preferences
    viewModel.commandPath.removeLast()
    XCTAssertEqual(viewModel.commandPath.last, .chartPreferences)

    // Simulates navigating to Offline Charts
    viewModel.commandPath.append(.offlineCharts)
    XCTAssertEqual(viewModel.commandPath.last, .offlineCharts)
  }
}
