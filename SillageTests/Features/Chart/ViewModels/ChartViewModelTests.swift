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
    let viewModel = ChartViewModel(
      positioningService: positioningService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: nil,
      messageService: messageService
    )
    
    // Wait for the background task to complete
    _ = await viewModel.silentFetchTask?.task.value
    
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
    let viewModel = ChartViewModel(
      positioningService: positioningService,
      preferencesService: preferencesService,
      authService: mockAuthService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: nil,
      messageService: messageService
    )
    
    // Wait for the background task to complete
    _ = await viewModel.silentFetchTask?.task.value
    
    // Assert
    XCTAssertEqual(messageService.messages.count, 0, "No message should be posted to MessageService on network failure (offline mode)")
    
    // Clean up
    KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    _ = viewModel // Keep strong reference alive
  }
}
