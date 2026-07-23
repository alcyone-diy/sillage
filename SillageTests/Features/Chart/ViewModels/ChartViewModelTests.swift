//
//  ChartViewModelTests.swift
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
import CoreLocation



@MainActor
final class ChartViewModelTests: XCTestCase {

  func testSilentAuthFailurePostsDismissableMessage() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.shouldFailFetchAccountSettings = true
    let messageService = MessageService()
    
    // We need to set a dummy token so it actually attempts the silent fetch
    KeychainManager.shared.save(token: "dummy_token", for: "geogarage_access_token")
    
    let preferencesService = PreferencesService()
    let positioningService = MockPositioningService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    

    // Act
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: nil,
      messageService: messageService
    )
    
    // Wait for the background task to complete
    if let task = viewModel.silentFetchTask?.task {
      _ = await task.value
    }
    
    _ = viewModel // Keep strong reference alive

    // Assert
    XCTAssertEqual(messageService.messages.count, 1, "A message should be posted to MessageService on silent auth fetch failure")
    
    if let firstMessage = messageService.messages.first {
      XCTAssertEqual(firstMessage.category, .geoGarage)
      XCTAssertTrue(firstMessage.isDismissable, "The posted authentication error message must have its dismissable property set to true")
    }
    
    // Clean up
    KeychainManager.shared.deleteToken(for: "geogarage_access_token")
  }

  func testSilentAuthNetworkFailureIgnoresMessage() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.shouldFailWithNetworkError = true
    let messageService = MessageService()
    
    KeychainManager.shared.save(token: "dummy_token", for: "geogarage_access_token")
    
    // Create dependencies
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    

    // Act
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: nil,
      messageService: messageService
    )
    
    // Wait for the background task to complete
    if let task = viewModel.silentFetchTask?.task {
      _ = await task.value
    }
    
    // Assert
    XCTAssertEqual(messageService.messages.count, 0, "No message should be posted to MessageService on network failure (offline mode)")
    
    // Clean up
    KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    _ = viewModel // Keep strong reference alive
  }

  func testUpdateGeoGarageLayersClearsGeoGarageMessages() async {
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
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)

    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let viewModel = ChartViewModel(
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
    let newLayer = GeoGarageLayer(layer: "layer1", brand_name: "Brand", version_date: "2026-01-01", valid_until: "2030-01-01")
    viewModel.updateGeoGarageLayers([newLayer])

    // Assert
    XCTAssertEqual(messageService.messages.count, 0, "Calling updateGeoGarageLayers should clear .geoGarage messages in MessageService")
    XCTAssertEqual(viewModel.availableGeoGarageLayers.count, 1)
    _ = viewModel
  }

  func testSilentAuthSuccessClearsGeoGarageMessages() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.shouldFailFetchAccountSettings = false
    let messageService = MessageService()
    let initialMessage = AppMessage(
      title: "Auth Error",
      detail: "Invalid credentials",
      severity: .error,
      category: .geoGarage
    )
    messageService.post(initialMessage)
    XCTAssertEqual(messageService.messages.count, 1)

    KeychainManager.shared.save(token: "valid_token", for: "geogarage_access_token")

    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)

    // Act
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: nil,
      messageService: messageService
    )

    // Wait for the background task to complete
    if let task = viewModel.silentFetchTask?.task {
      _ = await task.value
    }

    // Assert
    XCTAssertEqual(messageService.messages.count, 0, "Successful silent auth fetch should clear .geoGarage messages in MessageService")

    // Clean up
    KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    _ = viewModel
  }

  func testUpdateGeoGarageLayersClearsOnlyGeoGarageMessagesWhenMultipleCategoriesExist() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()

    let geoMsg1 = AppMessage(title: "Auth Error 1", detail: "Invalid token", severity: .error, category: .geoGarage)
    let netMsg = AppMessage(title: "Network Error", detail: "Offline", severity: .warning, category: .network)
    let weatherMsg = AppMessage(title: "Weather Alert", detail: "Gale Warning", severity: .warning, category: .weather)
    let geoMsg2 = AppMessage(title: "Auth Error 2", detail: "Expired subscription", severity: .error, category: .geoGarage)

    messageService.post(geoMsg1)
    messageService.post(netMsg)
    messageService.post(weatherMsg)
    messageService.post(geoMsg2)

    XCTAssertEqual(messageService.messages.count, 4)

    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)

    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let viewModel = ChartViewModel(
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
    let newLayer = GeoGarageLayer(layer: "layer1", brand_name: "Brand", version_date: "2026-01-01", valid_until: "2030-01-01")
    viewModel.updateGeoGarageLayers([newLayer])

    // Assert
    XCTAssertEqual(messageService.messages.count, 2, "Only .geoGarage messages should be removed, non-geoGarage messages must remain")
    let remainingCategories = Set(messageService.messages.map { $0.category })
    XCTAssertTrue(remainingCategories.contains(.network))
    XCTAssertTrue(remainingCategories.contains(.weather))
    XCTAssertFalse(remainingCategories.contains(.geoGarage), "No .geoGarage messages should remain after updateGeoGarageLayers")
    _ = viewModel
  }

  func testSilentAuthSuccessClearsOnlyGeoGarageMessagesWhenMultipleCategoriesExist() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.shouldFailFetchAccountSettings = false
    let messageService = MessageService()

    let geoMsg = AppMessage(title: "Auth Error", detail: "Invalid token", severity: .error, category: .geoGarage)
    let netMsg = AppMessage(title: "Network Error", detail: "Disconnected", severity: .error, category: .network)
    let weatherMsg = AppMessage(title: "Weather Alert", detail: "Squall", severity: .warning, category: .weather)

    messageService.post(geoMsg)
    messageService.post(netMsg)
    messageService.post(weatherMsg)

    XCTAssertEqual(messageService.messages.count, 3)

    KeychainManager.shared.save(token: "valid_token", for: "geogarage_access_token")

    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)

    // Act
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: nil,
      messageService: messageService
    )

    // Wait for the background task to complete
    if let task = viewModel.silentFetchTask?.task {
      _ = await task.value
    }

    // Assert
    XCTAssertEqual(messageService.messages.count, 2, "Silent auth success should clear ONLY .geoGarage messages")
    let remainingCategories = Set(messageService.messages.map { $0.category })
    XCTAssertTrue(remainingCategories.contains(.network))
    XCTAssertTrue(remainingCategories.contains(.weather))
    XCTAssertFalse(remainingCategories.contains(.geoGarage))

    // Clean up
    KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    _ = viewModel
  }

  func testUpdateGeoGarageLayersWithEmptyLayersClearsGeoGarageMessages() async {
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
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)

    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let viewModel = ChartViewModel(
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
    viewModel.updateGeoGarageLayers([])

    // Assert
    XCTAssertTrue(viewModel.availableGeoGarageLayers.isEmpty)
    XCTAssertEqual(messageService.messages.count, 0, "Calling updateGeoGarageLayers([]) with empty list should clear .geoGarage messages in MessageService")
    _ = viewModel
  }

  func testUpdateGeoGarageLayersWithNilMessageServiceDoesNotCrash() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)

    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: nil,
      messageService: nil
    )

    // Act & Assert (Should not crash when messageService is nil)
    viewModel.updateGeoGarageLayers([])
    XCTAssertTrue(viewModel.availableGeoGarageLayers.isEmpty)

    let layer = GeoGarageLayer(layer: "layer1", brand_name: "Brand", version_date: "2026-01-01", valid_until: "2030-01-01")
    viewModel.updateGeoGarageLayers([layer])
    XCTAssertEqual(viewModel.availableGeoGarageLayers.count, 1)
    _ = viewModel
  }

  func testLogoutGeoGarageClearsMessagesAndLayers() async {
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
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)

    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: nil,
      messageService: messageService
    )

    let layer = GeoGarageLayer(layer: "layer1", brand_name: "Brand", version_date: "2026-01-01", valid_until: "2030-01-01")
    viewModel.updateGeoGarageLayers([layer])

    // Act
    viewModel.logoutGeoGarage()

    // Assert
    XCTAssertTrue(viewModel.availableGeoGarageLayers.isEmpty)
    XCTAssertEqual(messageService.messages.count, 0, "logoutGeoGarage should clear .geoGarage messages in MessageService")
    _ = viewModel
  }
}

