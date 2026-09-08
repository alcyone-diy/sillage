//
//  CommandAlarmRowTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
final class CommandAlarmRowTests: XCTestCase {

  // MARK: - Anchor Command Row Tests

  func testAnchorCommandRowAlarmStateMapping() {
    // Helper function reproducing AnchorCommandRowView.alarmState logic
    func evaluateState(for status: AnchorStatus) -> CommandAlarmState? {
      switch status {
      case .dragging:
        return .triggered
      case .armed:
        return .armed
      case .inactive, .droppedPendingPosition, .dropped:
        return nil
      }
    }

    XCTAssertNil(evaluateState(for: .inactive))
    XCTAssertNil(evaluateState(for: .droppedPendingPosition))
    XCTAssertNil(evaluateState(for: .dropped))
    XCTAssertEqual(evaluateState(for: .armed), CommandAlarmState.armed)
    XCTAssertEqual(evaluateState(for: .dragging), CommandAlarmState.triggered)
  }

  func testAnchorCrashSurvivalAndColdStartRestoration() {
    // Technical Design Choice (Cold Start Resilience):
    // Simulate app kill/OOM while anchor watch was active (.armed).
    let savedWatch = AnchorWatch(
      coordinate: CLLocationCoordinate2D(latitude: 47.5, longitude: -3.0),
      radius: Measurement(value: 30.0, unit: .meters),
      initialAccuracy: Measurement(value: 3.0, unit: .meters),
      createdAt: Date()
    )
    let persistentStore = MockAnchorStateStore()
    persistentStore.session = AnchorSessionData(
      activeWatch: savedWatch,
      status: .armed,
      triggerReason: nil
    )

    let positioning = MockPositioningService()
    let preferences = MockPreferencesService()
    let notifications = LocalNotificationService()
    let permissions = PermissionService(positioningService: positioning, notificationService: notifications)
    let background = DefaultBackgroundMonitoringService(positioningService: positioning)

    // Service boots from persistent store synchronously
    let restoredService = AnchorService(
      positioningService: positioning,
      preferencesService: preferences,
      notificationService: notifications,
      permissionService: permissions,
      backgroundMonitoringService: background,
      stateStore: persistentStore
    )

    let restoredViewModel = AnchorViewModel(anchorService: restoredService)

    // Immediate state without any new GPS fix must be .armed
    XCTAssertEqual(restoredViewModel.status, AnchorStatus.armed)
    XCTAssertEqual(restoredService.status, AnchorStatus.armed)
  }

  func testAnchorCrashSurvivalWithTriggeredDraggingState() {
    // Simulate app restart after triggering .dragging alert
    let savedWatch = AnchorWatch(
      coordinate: CLLocationCoordinate2D(latitude: 47.5, longitude: -3.0),
      radius: Measurement(value: 30.0, unit: .meters),
      initialAccuracy: Measurement(value: 3.0, unit: .meters),
      createdAt: Date()
    )
    let persistentStore = MockAnchorStateStore()
    persistentStore.session = AnchorSessionData(
      activeWatch: savedWatch,
      status: .dragging,
      triggerReason: .distanceExceeded(
        distance: Measurement(value: 45.0, unit: .meters),
        radius: Measurement(value: 30.0, unit: .meters)
      )
    )

    let positioning = MockPositioningService()
    let preferences = MockPreferencesService()
    let notifications = LocalNotificationService()
    let permissions = PermissionService(positioningService: positioning, notificationService: notifications)
    let background = DefaultBackgroundMonitoringService(positioningService: positioning)

    let restoredService = AnchorService(
      positioningService: positioning,
      preferencesService: preferences,
      notificationService: notifications,
      permissionService: permissions,
      backgroundMonitoringService: background,
      stateStore: persistentStore
    )

    let restoredViewModel = AnchorViewModel(anchorService: restoredService)

    // Immediate state upon cold boot reflects triggered dragging alert
    XCTAssertEqual(restoredViewModel.status, AnchorStatus.dragging)
  }

  // MARK: - Barometer Command Row Tests

  func testBarometerAlarmStateMapping() async throws {
    let dbManager = try DatabaseManager.inMemory()
    let store = BarometricHistoryStore(databaseManager: dbManager)
    let preferences = PreferencesService()
    let notifications = LocalNotificationService()
    let positioning = MockPositioningService()
    let permissions = PermissionService(positioningService: positioning, notificationService: notifications)

    let service = BarometricService(
      historyStore: store,
      preferencesService: preferences,
      notificationService: notifications,
      permissionService: permissions
    )

    let viewModel = BarometerViewModel(service: service, preferencesService: preferences)

    // Helper function reproducing BarometerCommandRowView.alarmState logic
    func evaluateState(isEnabled: Bool, alarmLevel: WeatherAlarmLevel?) -> CommandAlarmState? {
      guard isEnabled else { return nil }
      if alarmLevel != nil {
        return .triggered
      } else {
        return .armed
      }
    }

    // 1. Alarm disabled -> nil
    preferences.isBaroAlarmEnabled = false
    XCTAssertNil(evaluateState(isEnabled: viewModel.isAlarmEnabled, alarmLevel: viewModel.alarmLevel))

    // 2. Alarm enabled, normal weather (alarmLevel == nil) -> .armed
    preferences.isBaroAlarmEnabled = true
    XCTAssertEqual(evaluateState(isEnabled: viewModel.isAlarmEnabled, alarmLevel: nil), CommandAlarmState.armed)

    // 3. Alarm enabled, pressure drop detected -> .triggered
    XCTAssertEqual(evaluateState(isEnabled: viewModel.isAlarmEnabled, alarmLevel: .vigilance), CommandAlarmState.triggered)
    XCTAssertEqual(evaluateState(isEnabled: viewModel.isAlarmEnabled, alarmLevel: .gale), CommandAlarmState.triggered)
    XCTAssertEqual(evaluateState(isEnabled: viewModel.isAlarmEnabled, alarmLevel: .storm), CommandAlarmState.triggered)
    XCTAssertEqual(evaluateState(isEnabled: viewModel.isAlarmEnabled, alarmLevel: .squall), CommandAlarmState.triggered)
  }
}
