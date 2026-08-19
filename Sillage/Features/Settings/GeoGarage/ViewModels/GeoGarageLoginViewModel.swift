//
//  GeoGarageLoginViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import OSLog

enum GeoGarageViewState {
  case unauthenticated(error: String?)
  case authenticated(username: String?)
  case authenticationError(error: String, username: String?)
  case reauthenticating(error: String, username: String?)
}

@MainActor
@Observable
final class GeoGarageLoginViewModel {
  var username = ""
  var password = ""
  var isLoading = false
  var availableLayers: [GeoGarageLayer] = []
  var isAuthorizationReady: Bool = false
  var forceReauthentication: Bool = false

  var errorMessage: String?
  
  func currentError(authService: GeoGarageAuthServiceProtocol) -> String? {
    if let errorMessage {
      return errorMessage
    }
    if let authError = authService.authError {
      return authError.localizedDescription
    }
    return nil
  }

  func savedUsername(authService: GeoGarageAuthServiceProtocol) -> String? {
    authService.savedUsername
  }
  
  func discoverURL(authService: GeoGarageAuthServiceProtocol) -> URL? {
    authService.discoverURL
  }
  
  func accountManagementURL(authService: GeoGarageAuthServiceProtocol) -> URL? {
    authService.accountManagementURL
  }

  var isAuthenticated: Bool {
    KeychainManager.shared.retrieveTokenSync(for: "geogarage_access_token") != nil
  }

  func viewState(authService: GeoGarageAuthServiceProtocol) -> GeoGarageViewState {
    let currentSavedUsername = savedUsername(authService: authService)
    let currentErrorMsg = currentError(authService: authService)
    if isAuthenticated {
      if forceReauthentication {
        return .reauthenticating(error: currentErrorMsg ?? String(localized: "Authentication required"), username: currentSavedUsername)
      } else if let error = currentErrorMsg {
        return .authenticationError(error: error, username: currentSavedUsername)
      } else {
        return .authenticated(username: currentSavedUsername)
      }
    } else {
      return .unauthenticated(error: currentErrorMsg)
    }
  }

  var loginTask: Task<Void, Never>?

  private let offlineMapManager: OfflineMapManagerProtocol

  init(offlineMapManager: OfflineMapManagerProtocol) {
    self.offlineMapManager = offlineMapManager
  }

  func requiresOfflineMapsWarning() -> Bool {
    return !offlineMapManager.downloadedRegions.isEmpty
  }

  @MainActor
  func performLogout(
    authService: GeoGarageAuthServiceProtocol,
    messageService: MessageService?,
    chartViewModel: ChartViewModel
  ) async {
    loginTask?.cancel()
    password = ""
    availableLayers = []
    isAuthorizationReady = false
    errorMessage = nil
    forceReauthentication = false
    await authService.logout()
    messageService?.clear(category: .geoGarage)
    chartViewModel.logoutGeoGarage()
    
    do {
      try await offlineMapManager.deleteAllPacks()
    } catch {
      Logger.offline.error("Failed to delete offline packs during logout: \(error.localizedDescription, privacy: .public)")
      let appMessage = AppMessage(
        title: LocalizedStringResource("Offline Maps Error"),
        detail: LocalizedStringResource("Failed to delete some offline maps. Please check your storage."),
        severity: .error,
        category: .geoGarage
      )
      messageService?.post(appMessage)
    }
    
    try? await offlineMapManager.clearAmbientCache()
    
    if case .remoteGeoGarage = chartViewModel.currentChartSource {
      chartViewModel.switchChartSource(to: .openSeaMap)
    }
  }

  func login(authService: GeoGarageAuthServiceProtocol, messageService: MessageService?) {
    loginTask?.cancel()
    loginTask = Task { [weak self] in
      self?.isLoading = true

      defer {
        self?.isLoading = false
        self?.password = ""
      }

      guard let username = self?.username, let password = self?.password else { return }

      if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        self?.errorMessage = String(localized: "Please enter a valid username.")
        return
      }

      do {
        let response = try await authService.authenticate(username: username, password: password)

        // Save tokens securely
        await KeychainManager.shared.save(token: response.access_token, for: "geogarage_access_token")
        await KeychainManager.shared.save(token: response.refresh_token, for: "geogarage_refresh_token")

        // Save username for display
        authService.savedUsername = username

        // Fetch account settings/layers
        let settingsResponse = try await authService.fetchAccountSettings(accessToken: response.access_token)

        self?.availableLayers = settingsResponse.layers
        self?.isAuthorizationReady = true
        self?.forceReauthentication = false

        // Log successful fetch
        let layerNames = settingsResponse.layers.map { $0.brandName }.joined(separator: ", ")
        Logger.network.info("Successfully fetched layers: \(layerNames, privacy: .public)")
        
        // Clear any previous authentication error messages
        self?.errorMessage = nil
        messageService?.clear(category: .geoGarage)
      } catch let error as AuthError {
        self?.errorMessage = error.localizedDescription
      } catch {
        self?.errorMessage = AuthError.unknown.localizedDescription
      }
    }
  }

  func cancelLogin() {
    loginTask?.cancel()
  }
}
