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

  private func makeChartViewModel(authService: MockGeoGarageAuthService, messageService: MessageService) -> ChartViewModel {
    let positioningService = MockPositioningService()
    let preferencesService = PreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(positioningService: positioningService)
    let anchorService = AnchorService(positioningService: positioningService, preferencesService: preferencesService, notificationService: LocalNotificationService(), permissionService: permissionService, backgroundMonitoringService: backgroundMonitoringService)
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    return ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: authService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      waypointService: nil,
      messageService: messageService
    )
  }

  func testAuthenticationFailureSetsErrorMessage() async {
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.shouldFailAuthenticate = true
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: MockGeoGaragePartnerSecretService())

    viewModel.login(authService: mockAuthService, messageService: nil as MessageService?, presenter: MockGeoGarageAuthorizationPresenter())
    await viewModel.loginTask?.value

    XCTAssertNotNil(viewModel.errorMessage, "An error message should be set on auth failure")
    XCTAssertFalse(viewModel.isAuthorizationReady)
    XCTAssertFalse(viewModel.isLoading)
  }

  func testLoginHandsThePresenterToTheAuthService() async {
    let mockAuthService = MockGeoGarageAuthService()
    let presenter = MockGeoGarageAuthorizationPresenter()
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: MockGeoGaragePartnerSecretService())

    viewModel.login(authService: mockAuthService, messageService: nil as MessageService?, presenter: presenter)
    await viewModel.loginTask?.value

    XCTAssertTrue((mockAuthService.lastPresenter as? MockGeoGarageAuthorizationPresenter) === presenter)
    XCTAssertTrue(viewModel.isAuthorizationReady)
  }

  func testSuccessfulLoginClearsGeoGarageMessages() async {
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    messageService.post(AppMessage(title: "Auth Error", detail: "Invalid credentials", severity: .error, category: .geoGarage))
    XCTAssertEqual(messageService.messages.count, 1)
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: MockGeoGaragePartnerSecretService())

    viewModel.login(authService: mockAuthService, messageService: messageService, presenter: MockGeoGarageAuthorizationPresenter())
    await viewModel.loginTask?.value

    XCTAssertTrue(viewModel.isAuthorizationReady)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(messageService.messages.count, 0, "Successful login should clear .geoGarage messages in MessageService")
  }

  func testSuccessfulLoginClearsOnlyGeoGarageMessagesWhenMultipleCategoriesExist() async {
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    messageService.post(AppMessage(title: "Auth Error 1", detail: "Invalid password", severity: .error, category: .geoGarage))
    messageService.post(AppMessage(title: "Network Offline", detail: "No Wi-Fi/Cellular", severity: .warning, category: .network))
    messageService.post(AppMessage(title: "Weather Alert", detail: "Gale force 8", severity: .warning, category: .weather))
    messageService.post(AppMessage(title: "Auth Error 2", detail: "Account expired", severity: .error, category: .geoGarage))
    XCTAssertEqual(messageService.messages.count, 4)
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: MockGeoGaragePartnerSecretService())

    viewModel.login(authService: mockAuthService, messageService: messageService, presenter: MockGeoGarageAuthorizationPresenter())
    await viewModel.loginTask?.value

    XCTAssertTrue(viewModel.isAuthorizationReady)
    XCTAssertEqual(messageService.messages.count, 2, "Successful login should clear ONLY .geoGarage messages")
    let remainingCategories = Set(messageService.messages.map { $0.category })
    XCTAssertTrue(remainingCategories.contains(.network))
    XCTAssertTrue(remainingCategories.contains(.weather))
    XCTAssertFalse(remainingCategories.contains(.geoGarage))
  }

  func testSuccessfulLoginWithNilMessageServiceSucceedsWithoutCrash() async {
    let mockAuthService = MockGeoGarageAuthService()
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: MockGeoGaragePartnerSecretService())

    viewModel.login(authService: mockAuthService, messageService: nil as MessageService?, presenter: MockGeoGarageAuthorizationPresenter())
    await viewModel.loginTask?.value

    XCTAssertTrue(viewModel.isAuthorizationReady)
    XCTAssertNil(viewModel.errorMessage)
  }

  func testCancelledSignInLeavesNoErrorAndIsNotReady() async {
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.authErrorToThrow = .cancelled
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: MockGeoGaragePartnerSecretService())

    viewModel.login(authService: mockAuthService, messageService: nil as MessageService?, presenter: MockGeoGarageAuthorizationPresenter())
    await viewModel.loginTask?.value

    XCTAssertNil(viewModel.errorMessage, "Closing the GeoGarage page is not an error")
    XCTAssertFalse(viewModel.isAuthorizationReady)
    XCTAssertFalse(viewModel.isLoading)
  }

  func testAccessDeniedSetsSpecificErrorMessage() async {
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.authErrorToThrow = .accessDenied
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: MockGeoGaragePartnerSecretService())

    viewModel.login(authService: mockAuthService, messageService: nil as MessageService?, presenter: MockGeoGarageAuthorizationPresenter())
    await viewModel.loginTask?.value

    XCTAssertFalse(viewModel.isAuthorizationReady)
    XCTAssertEqual(viewModel.errorMessage, AuthError.accessDenied.localizedDescription)
  }

  func testSettingsFailureAfterSignInSetsErrorMessage() async {
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.shouldFailFetchAccountSettings = true
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: MockGeoGaragePartnerSecretService())

    viewModel.login(authService: mockAuthService, messageService: nil as MessageService?, presenter: MockGeoGarageAuthorizationPresenter())
    await viewModel.loginTask?.value

    XCTAssertFalse(viewModel.isAuthorizationReady)
    XCTAssertEqual(viewModel.errorMessage, AuthError.tokenExpired.localizedDescription)
  }

  func testViewStateReflectsAuthenticationAndErrors() {
    let mockAuthService = MockGeoGarageAuthService()
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: MockGeoGaragePartnerSecretService())
    KeychainManager.shared.deleteTokenSync(for: "geogarage_access_token")
    addTeardownBlock {
      await MainActor.run { KeychainManager.shared.deleteTokenSync(for: "geogarage_access_token") }
    }

    XCTAssertEqual(viewModel.viewState(authService: mockAuthService), .unauthenticated(error: nil))

    viewModel.errorMessage = "boom"
    XCTAssertEqual(viewModel.viewState(authService: mockAuthService), .unauthenticated(error: "boom"))

    viewModel.errorMessage = nil
    KeychainManager.shared.saveSync(token: "tok", for: "geogarage_access_token")
    XCTAssertEqual(viewModel.viewState(authService: mockAuthService), .authenticated)

    mockAuthService.authError = AuthError.tokenExpired
    XCTAssertEqual(viewModel.viewState(authService: mockAuthService), .authenticationError(error: AuthError.tokenExpired.localizedDescription))
  }

  func testLogoutClearsGeoGarageMessagesAndDelegatesToChartViewModel() async {
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    messageService.post(AppMessage(title: "Auth Error", detail: "Invalid credentials", severity: .error, category: .geoGarage))
    let chartViewModel = makeChartViewModel(authService: mockAuthService, messageService: messageService)
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: MockGeoGaragePartnerSecretService())
    viewModel.availableLayers = [GeoGarageLayer(layer: "l1", brandName: "Brand", versionDate: "2026-01-01", validUntil: "2030-01-01")]
    viewModel.isAuthorizationReady = true
    mockAuthService.availableLayers = viewModel.availableLayers
    chartViewModel.clearGeoGarageMessages()

    await viewModel.performLogout(authService: mockAuthService, messageService: messageService, chartViewModel: chartViewModel)

    XCTAssertTrue(viewModel.availableLayers.isEmpty)
    XCTAssertFalse(viewModel.isAuthorizationReady)
    XCTAssertTrue(chartViewModel.availableGeoGarageLayers.isEmpty)
    XCTAssertEqual(messageService.messages.count, 0)
    _ = chartViewModel
  }

  func testLogoutClearsGeoGarageMessagesAndAuthServiceState() async {
    let mockAuthService = MockGeoGarageAuthService()
    let messageService = MessageService()
    messageService.post(AppMessage(title: "Auth Error", detail: "Invalid credentials", severity: .error, category: .geoGarage))
    let chartViewModel = makeChartViewModel(authService: mockAuthService, messageService: messageService)
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: MockGeoGaragePartnerSecretService())
    viewModel.availableLayers = [GeoGarageLayer(layer: "l1", brandName: "Brand", versionDate: "2026-01-01", validUntil: "2030-01-01")]
    viewModel.isAuthorizationReady = true

    await viewModel.performLogout(authService: mockAuthService, messageService: messageService, chartViewModel: chartViewModel)

    XCTAssertTrue(viewModel.availableLayers.isEmpty)
    XCTAssertFalse(viewModel.isAuthorizationReady)
    XCTAssertFalse(mockAuthService.isGeoGarageAuthenticated)
    XCTAssertEqual(messageService.messages.count, 0)
  }

  // MARK: - Secret de déchiffrement des paquets (voie B, 11 sept. 2026)

  func testSecretFailureAfterSignInPostsWarningButStaysReady() async {
    let mockAuthService = MockGeoGarageAuthService()
    let secretService = MockGeoGaragePartnerSecretService()
    secretService.errorToThrow = .noProfile
    let messageService = MessageService()
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: secretService)

    viewModel.login(authService: mockAuthService, messageService: messageService, presenter: MockGeoGarageAuthorizationPresenter())
    await viewModel.loginTask?.value

    XCTAssertTrue(viewModel.isAuthorizationReady, "Le secret manquant ne bloque pas la connexion")
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertEqual(messageService.messages.count, 1)
    XCTAssertEqual(messageService.messages.first?.category, .geoGarage)
    XCTAssertEqual(messageService.messages.first?.severity, .warning)
  }

  func testSecretIsRefreshedWithTheFreshAccessToken() async {
    let mockAuthService = MockGeoGarageAuthService()
    let secretService = MockGeoGaragePartnerSecretService()
    let viewModel = GeoGarageLoginViewModel(offlineMapManager: MockOfflineMapManager(), partnerSecretService: secretService)

    viewModel.login(authService: mockAuthService, messageService: nil as MessageService?, presenter: MockGeoGarageAuthorizationPresenter())
    await viewModel.loginTask?.value

    XCTAssertEqual(secretService.receivedAccessTokens, ["mock_access"])
  }
}
