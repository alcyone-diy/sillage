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
    KeychainManager.shared.saveSync(token: "dummy_token", for: "geogarage_access_token")
    
    let preferencesService = PreferencesService()
    let positioningService = MockPositioningService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
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
    KeychainManager.shared.deleteTokenSync(for: "geogarage_access_token")
  }

  func testSilentAuthNetworkFailureIgnoresMessage() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.shouldFailWithNetworkError = true
    let messageService = MessageService()
    
    KeychainManager.shared.saveSync(token: "dummy_token", for: "geogarage_access_token")
    
    // Create dependencies
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
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
    KeychainManager.shared.deleteTokenSync(for: "geogarage_access_token")
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
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
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
    mockAuthService.availableLayers = [newLayer]
    viewModel.clearGeoGarageMessages()

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

    KeychainManager.shared.saveSync(token: "valid_token", for: "geogarage_access_token")

    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
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
    KeychainManager.shared.deleteTokenSync(for: "geogarage_access_token")
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
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
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
    viewModel.clearGeoGarageMessages()

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

    KeychainManager.shared.saveSync(token: "valid_token", for: "geogarage_access_token")

    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
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
    KeychainManager.shared.deleteTokenSync(for: "geogarage_access_token")
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
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
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
    viewModel.clearGeoGarageMessages()

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
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
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
    viewModel.clearGeoGarageMessages()
    let layer = GeoGarageLayer(layer: "layer1", brand_name: "Brand", version_date: "2026-01-01", valid_until: "2030-01-01")
    mockAuthService.availableLayers = [layer]
    viewModel.clearGeoGarageMessages()
    XCTAssertEqual(viewModel.availableGeoGarageLayers.count, 1)
    _ = viewModel
  }

  func testLogoutGeoGarageClearsMessagesAndLayers() async throws {
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
    mockAuthService.availableLayers = [layer]
    viewModel.clearGeoGarageMessages()

    // Act
    viewModel.logoutGeoGarage()
    try await waitFor { viewModel.availableGeoGarageLayers.isEmpty && messageService.messages.count == 0 }

    // Assert
    XCTAssertTrue(viewModel.availableGeoGarageLayers.isEmpty)
    XCTAssertEqual(messageService.messages.count, 0, "logoutGeoGarage should clear .geoGarage messages in MessageService")
    _ = viewModel
  }

  func testSwitchChartSourceToOpenSeaMapEnablesSeamarksOverlay() async {
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)

    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: MockGeoGarageAuthService(),
      anchorService: anchorService,
      anchorViewModel: anchorViewModel
    )

    viewModel.switchChartSource(to: .openSeaMap)

    XCTAssertTrue(viewModel.isOpenSeaMapOverlayEnabled, "OpenSeaMap seamark overlay must be automatically enabled when switching to OpenSeaMap chart source")
    XCTAssertTrue(preferencesService.isOpenSeaMapOverlayEnabled)
  }

  func testSwitchChartSourceToGeoGarageDisablesSeamarksOverlay() async {
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)

    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: MockGeoGarageAuthService(),
      anchorService: anchorService,
      anchorViewModel: anchorViewModel
    )

    viewModel.switchChartSource(to: .openSeaMap)
    XCTAssertTrue(viewModel.isOpenSeaMapOverlayEnabled)

    viewModel.switchChartSource(to: .remoteGeoGarage(clientID: "test_client", layerID: "test_layer"))
    XCTAssertFalse(viewModel.isOpenSeaMapOverlayEnabled, "OpenSeaMap seamark overlay must be automatically disabled when switching away from OpenSeaMap chart source")
    XCTAssertFalse(preferencesService.isOpenSeaMapOverlayEnabled)
  }

  func testIsActionConfirmationCardActive_StateToggle() {
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)

    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: MockGeoGarageAuthService(),
      anchorService: anchorService,
      anchorViewModel: anchorViewModel
    )

    XCTAssertFalse(viewModel.isActionConfirmationCardActive)
    
    // 1. Activated via manual anchor position adjustment
    anchorViewModel.startAdjustingAnchor()
    XCTAssertTrue(viewModel.isActionConfirmationCardActive)
    anchorViewModel.cancelAdjustAnchor()
    XCTAssertFalse(viewModel.isActionConfirmationCardActive)

    // 2. Activated via drop anchor preparation mode
    anchorViewModel.startPreparingDropAnchor()
    XCTAssertTrue(viewModel.isActionConfirmationCardActive)
    anchorViewModel.cancelPreparingDropAnchor()
    XCTAssertFalse(viewModel.isActionConfirmationCardActive)
  }

  func testCenterOnUserLocation_PreservesZoom() async {
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    instrumentDampingService.start()

    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: MockGeoGarageAuthService(),
      anchorService: anchorService,
      anchorViewModel: anchorViewModel
    )

    let expectedCoord = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
    let fix = NavigationFix(
      coordinate: expectedCoord,
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    let stream = viewModel.cameraMoveStream
    let task = Task<CameraMoveEvent?, Never> {
      await withTaskGroup(of: CameraMoveEvent?.self) { group in
        group.addTask {
          var iterator = stream.makeAsyncIterator()
          return await iterator.next()
        }
        group.addTask {
          try? await Task.sleep(for: .seconds(2))
          return nil
        }
        let firstResult = await group.next()
        group.cancelAll()
        return firstResult.flatMap { $0 }
      }
    }

    await Task.yield()

    positioningService.locationContinuation?.yield(.active(fix))
    await Task.yield()

    viewModel.centerOnUserLocation()

    let receivedEvent = await task.value

    if case .center(let coordinate, let zoom, _) = receivedEvent {
      XCTAssertEqual(coordinate.latitude, expectedCoord.latitude, accuracy: 0.0001)
      XCTAssertEqual(coordinate.longitude, expectedCoord.longitude, accuracy: 0.0001)
      XCTAssertNil(zoom, "Zoom must be nil to preserve current zoom level")
    } else {
      XCTFail("Expected CameraMoveEvent.center event but got \(String(describing: receivedEvent))")
    }
  }

  func testThrottledUpdateCenterCoordinate_AppliesTrailingEdgeThrottlingAndThreshold() async throws {
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)

    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: MockGeoGarageAuthService(),
      anchorService: anchorService,
      anchorViewModel: anchorViewModel
    )

    let initialCenter = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    viewModel.updateCenterCoordinateImmediately(initialCenter)
    XCTAssertEqual(viewModel.centerCoordinate.latitude, 47.0)

    // 1. Movement smaller than 1.0m threshold via throttled update
    let tinyShift = CLLocationCoordinate2D(latitude: 47.000001, longitude: -3.0) // ~0.1m
    viewModel.throttledUpdateCenterCoordinate(tinyShift)

    // Wait for throttle interval to expire
    try await Task.sleep(for: AppConstants.Map.regionThrottleInterval + .milliseconds(50))
    XCTAssertEqual(viewModel.centerCoordinate.latitude, 47.0, "Sub-meter movement should be ignored by throttled update threshold")

    // 2. Trailing Edge Throttle Test: Multiple rapid updates during throttle sleep window
    let firstShift = CLLocationCoordinate2D(latitude: 47.01, longitude: -3.0) // ~1.1km
    let latestShift = CLLocationCoordinate2D(latitude: 47.05, longitude: -3.0) // ~5.5km

    viewModel.throttledUpdateCenterCoordinate(firstShift)
    // Immediately overwrite with a fresher coordinate before throttle sleep expires
    viewModel.throttledUpdateCenterCoordinate(latestShift)

    // Right after calling throttled updates, centerCoordinate is not yet updated
    XCTAssertEqual(viewModel.centerCoordinate.latitude, 47.0)

    // Wait for throttle interval to expire
    try await Task.sleep(for: AppConstants.Map.regionThrottleInterval + .milliseconds(50))
    // Trailing edge throttling guarantees latestShift is applied, NOT firstShift
    XCTAssertEqual(viewModel.centerCoordinate.latitude, 47.05, "Trailing edge throttle must apply the latest coordinate received during the sleep window")

    // 3. Immediate update forces exact coordinate regardless of threshold and clears pending state
    let exactShift = CLLocationCoordinate2D(latitude: 47.08, longitude: -3.0)
    viewModel.updateCenterCoordinateImmediately(exactShift)
    XCTAssertEqual(viewModel.centerCoordinate.latitude, 47.08, "Immediate update should set exact coordinate instantly")
  }

  func testThrottledUpdateMapScaleAndZoom_AppliesTrailingEdgeThrottling() async throws {
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)

    let viewModel = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: MockGeoGarageAuthService(),
      anchorService: anchorService,
      anchorViewModel: anchorViewModel
    )

    viewModel.updateMapScaleAndZoomImmediately(metersPerPoint: 10.0, zoomLevel: 12.0)
    XCTAssertEqual(viewModel.mapScale?.converted(to: .meters).value, 10.0)
    XCTAssertEqual(viewModel.zoomLevel, 12.0)

    // Trailing Edge Throttle Test: Multiple rapid updates during throttle sleep window
    viewModel.throttledUpdateMapScaleAndZoom(metersPerPoint: 20.0, zoomLevel: 14.0)
    viewModel.throttledUpdateMapScaleAndZoom(metersPerPoint: 35.0, zoomLevel: 16.0)

    // Throttled update should not apply immediately
    XCTAssertEqual(viewModel.mapScale?.converted(to: .meters).value, 10.0)
    XCTAssertEqual(viewModel.zoomLevel, 12.0)

    // Wait for throttle interval to expire
    try await Task.sleep(for: AppConstants.Map.regionThrottleInterval + .milliseconds(50))
    // Trailing edge throttling guarantees latest scale and zoom level are applied
    XCTAssertEqual(viewModel.mapScale?.converted(to: .meters).value, 35.0)
    XCTAssertEqual(viewModel.zoomLevel, 16.0)
  }
}


