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
    _ = await viewModel.login(authService: mockAuthService, messageService: nil as MessageService?)

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
    _ = await viewModel.login(authService: mockAuthService, messageService: messageService)

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
    _ = await viewModel.login(authService: mockAuthService, messageService: messageService)

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
    _ = await viewModel.login(authService: mockAuthService, messageService: nil as MessageService?)

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
    _ = await viewModel.login(authService: mockAuthService, messageService: nil as MessageService?)

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
    _ = await viewModel.login(authService: mockAuthService, messageService: nil as MessageService?)

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
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
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
    viewModel.availableLayers = [GeoGarageLayer(layer: "l1", brandName: "Brand", versionDate: "2026-01-01", validUntil: "2030-01-01")]
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
    viewModel.availableLayers = [GeoGarageLayer(layer: "l1", brandName: "Brand", versionDate: "2026-01-01", validUntil: "2030-01-01")]
    viewModel.isAuthorizationReady = true

    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
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

  func testPasswordWipedFromMemoryAfterLoginAttempt() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager())
    viewModel.username = "testuser"
    viewModel.password = "secret_password_123"

    // Act
    _ = await viewModel.login(authService: mockAuthService, messageService: nil as MessageService?)

    // Assert
    XCTAssertEqual(viewModel.password, "", "Password must be wiped from memory immediately after login completion")

    _ = viewModel
  }

  func testInvalidCredentialsSetsSpecificErrorMessage() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.authErrorToThrow = AuthError.invalidCredentials
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager())
    viewModel.username = "baduser"
    viewModel.password = "wrongpass"

    // Act
    _ = await viewModel.login(authService: mockAuthService, messageService: nil as MessageService?)

    // Assert
    XCTAssertFalse(viewModel.isAuthorizationReady)
    XCTAssertEqual(viewModel.errorMessage, AuthError.invalidCredentials.localizedDescription)
    XCTAssertEqual(viewModel.password, "", "Password must be wiped even when authentication fails")

    _ = viewModel
  }

  func testContextInjectionPreservedImmutably() {
    let setupVM = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), context: .initialSetup)
    XCTAssertEqual(setupVM.context, .initialSetup)

    let reauthVM = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), context: .reauthentication)
    XCTAssertEqual(reauthVM.context, .reauthentication)
  }

  func testAsyncLoginReturnsSuccessAndDecouplesChartViewModel() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService
    )
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

    let viewModel = GeoGarageLoginViewModel(
      offlineMapManager: MockOfflineMapManager(),
      context: .initialSetup
    )
    viewModel.username = "testuser"
    viewModel.password = "testpass"

    // Act
    let success = await viewModel.login(
      authService: mockAuthService,
      messageService: messageService
    )

    if success {
      // Orchestration at View/Coordinator level
      chartViewModel.handleGeoGarageLoginSuccess(
        context: viewModel.context,
        availableLayers: viewModel.availableLayers
      )
    }

    // Assert
    XCTAssertTrue(success)
    XCTAssertTrue(viewModel.isAuthorizationReady)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(viewModel.password, "")
    _ = viewModel
  }
}

