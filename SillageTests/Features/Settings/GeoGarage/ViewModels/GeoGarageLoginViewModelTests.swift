//
//  GeoGarageLoginViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import SwiftUI
@testable import Sillage


@MainActor
final class GeoGarageLoginViewModelTests: XCTestCase {

  func testAuthenticationFailureSetsErrorMessage() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.shouldFailAuthenticate = true
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager())

    viewModel.username = "testuser"
    viewModel.password = "testpass"

    // Act
    viewModel.login(authService: mockAuthService, messageService: nil as MessageService?)
    
    // Await the task cleanly instead of polling
    await viewModel.loginTask?.value

    // Assert
    XCTAssertNotNil(viewModel.errorMessage, "An error message should be set on auth failure")
    
    _ = viewModel // Keep strong reference alive
  }

  func testSuccessfulLoginClearsGeoGarageMessages() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    let initialMessage = AppMessage(
      title: "Auth Error",
      detail: "Invalid credentials",
      severity: .error,
      category: .geoGarage
    )
    messageService.post(initialMessage)
    XCTAssertEqual(messageService.messages.count, 1)

    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager())
    viewModel.username = "testuser"
    viewModel.password = "testpass"

    // Act
    viewModel.login(authService: mockAuthService, messageService: messageService)

    // Await the task cleanly instead of polling
    await viewModel.loginTask?.value

    // Assert
    XCTAssertTrue(viewModel.isAuthorizationReady)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(messageService.messages.count, 0, "Successful login should clear .geoGarage messages in MessageService")

    _ = viewModel
  }

  func testSuccessfulLoginClearsOnlyGeoGarageMessagesWhenMultipleCategoriesExist() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()

    let geoMsg1 = AppMessage(title: "Auth Error 1", detail: "Invalid password", severity: .error, category: .geoGarage)
    let netMsg = AppMessage(title: "Network Offline", detail: "No Wi-Fi/Cellular", severity: .warning, category: .network)
    let weatherMsg = AppMessage(title: "Weather Alert", detail: "Gale force 8", severity: .warning, category: .weather)
    let geoMsg2 = AppMessage(title: "Auth Error 2", detail: "Account expired", severity: .error, category: .geoGarage)

    messageService.post(geoMsg1)
    messageService.post(netMsg)
    messageService.post(weatherMsg)
    messageService.post(geoMsg2)

    XCTAssertEqual(messageService.messages.count, 4)

    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager())
    viewModel.username = "testuser"
    viewModel.password = "testpass"

    // Act
    viewModel.login(authService: mockAuthService, messageService: messageService)

    // Await the task cleanly
    await viewModel.loginTask?.value

    // Assert
    XCTAssertTrue(viewModel.isAuthorizationReady)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(messageService.messages.count, 2, "Successful login should clear ONLY .geoGarage messages")

    let remainingCategories = Set(messageService.messages.map { $0.category })
    XCTAssertTrue(remainingCategories.contains(.network))
    XCTAssertTrue(remainingCategories.contains(.weather))
    XCTAssertFalse(remainingCategories.contains(.geoGarage), "No .geoGarage messages should remain after successful login")

    _ = viewModel
  }

  func testSuccessfulLoginWithNilMessageServiceSucceedsWithoutCrash() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager())
    viewModel.username = "testuser"
    viewModel.password = "testpass"

    // Act
    viewModel.login(authService: mockAuthService, messageService: nil as MessageService?)

    // Await the task cleanly
    await viewModel.loginTask?.value

    // Assert
    XCTAssertTrue(viewModel.isAuthorizationReady)
    XCTAssertNil(viewModel.errorMessage)

    _ = viewModel
  }

  func testLoginFailureWithNilMessageServiceSetsErrorWithoutCrash() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.shouldFailAuthenticate = true
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager())
    viewModel.username = "testuser"
    viewModel.password = "testpass"

    // Act
    viewModel.login(authService: mockAuthService, messageService: nil as MessageService?)

    // Await the task cleanly
    await viewModel.loginTask?.value

    // Assert
    XCTAssertFalse(viewModel.isAuthorizationReady)
    XCTAssertNotNil(viewModel.errorMessage)

    _ = viewModel
  }

  func testLoginWithEmptyUsernameDoesNotAttemptAuthOrCrash() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager())
    viewModel.username = "   "
    viewModel.password = "testpass"

    // Act
    viewModel.login(authService: mockAuthService, messageService: nil as MessageService?)

    // Await task
    await viewModel.loginTask?.value

    // Assert
    XCTAssertFalse(viewModel.isAuthorizationReady)
    XCTAssertEqual(viewModel.errorMessage, String(localized: "Please enter a valid username."))

    _ = viewModel
  }

  func testLogoutClearsGeoGarageMessagesAndDelegatesToChartViewModel() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    let initialMessage = AppMessage(
      title: "Auth Error",
      detail: "Invalid credentials",
      severity: .error,
      category: .geoGarage
    )
    messageService.post(initialMessage)
    XCTAssertEqual(messageService.messages.count, 1)

    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)

    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let chartViewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: nil,
      messageService: messageService
    )

    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager())
    viewModel.availableLayers = [GeoGarageLayer(layer: "l1", brand_name: "Brand", version_date: "2026-01-01", valid_until: "2030-01-01")]
    viewModel.isAuthorizationReady = true
    mockAuthService.availableLayers = viewModel.availableLayers
    chartViewModel.clearGeoGarageMessages()

    // Act
    await viewModel.performLogout(authService: mockAuthService, messageService: messageService, chartViewModel: chartViewModel)

    // Assert
    XCTAssertTrue(viewModel.availableLayers.isEmpty)
    XCTAssertFalse(viewModel.isAuthorizationReady)
    XCTAssertTrue(chartViewModel.availableGeoGarageLayers.isEmpty)
    XCTAssertEqual(messageService.messages.count, 0, "Logout should clear .geoGarage messages in MessageService and reset layers in ChartViewModel")

    _ = viewModel
    _ = chartViewModel
  }

  func testLogoutClearsGeoGarageMessagesAndAuthServiceState() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    let initialMessage = AppMessage(
      title: "Auth Error",
      detail: "Invalid credentials",
      severity: .error,
      category: .geoGarage
    )
    messageService.post(initialMessage)
    XCTAssertEqual(messageService.messages.count, 1)

    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager())
    viewModel.availableLayers = [GeoGarageLayer(layer: "l1", brand_name: "Brand", version_date: "2026-01-01", valid_until: "2030-01-01")]
    viewModel.isAuthorizationReady = true

    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let chartViewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: nil,
      messageService: messageService
    )

    // Act
    await viewModel.performLogout(authService: mockAuthService, messageService: messageService, chartViewModel: chartViewModel)

    // Assert
    XCTAssertTrue(viewModel.availableLayers.isEmpty)
    XCTAssertFalse(viewModel.isAuthorizationReady)
    XCTAssertEqual(messageService.messages.count, 0, "Logout should clear .geoGarage messages in MessageService")

    _ = viewModel
  }
}

