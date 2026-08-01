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

  var currentError: String? {
    if let errorMessage {
      return errorMessage
    }
    if let authError = authService.authError {
      return authError.localizedDescription
    }
    return nil
  }

  var savedUsername: String? {
    authService.savedUsername
  }
  
  var discoverURL: URL {
    authService.discoverURL
  }
  
  var accountManagementURL: URL {
    authService.accountManagementURL
  }

  var isAuthenticated: Bool {
    KeychainManager.shared.retrieveToken(for: "geogarage_access_token") != nil
  }

  var viewState: GeoGarageViewState {
    if isAuthenticated {
      if forceReauthentication {
        return .reauthenticating(error: currentError ?? String(localized: "Authentication required"), username: savedUsername)
      } else if let error = currentError {
        return .authenticationError(error: error, username: savedUsername)
      } else {
        return .authenticated(username: savedUsername)
      }
    } else {
      return .unauthenticated(error: currentError)
    }
  }

  private let authService: GeoGarageAuthServiceProtocol
  var messageService: MessageService?
  var loginTask: Task<Void, Never>?

  init(authService: GeoGarageAuthServiceProtocol, messageService: MessageService? = nil) {
    self.authService = authService
    self.messageService = messageService
  }

  func logout() {
    loginTask?.cancel()
    availableLayers = []
    isAuthorizationReady = false
    errorMessage = nil
    forceReauthentication = false
    authService.logout()
    messageService?.clear(category: .geoGarage)
  }

  func login() {
    loginTask?.cancel()
    loginTask = Task { [weak self] in
      self?.isLoading = true

      defer { self?.isLoading = false }

      guard let username = self?.username, let password = self?.password else { return }

      if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        self?.errorMessage = String(localized: "Please enter a valid username.")
        return
      }

      do {
        guard let authService = self?.authService else { return }
        let response = try await authService.authenticate(username: username, password: password)

        // Save tokens securely
        KeychainManager.shared.save(token: response.access_token, for: "geogarage_access_token")
        KeychainManager.shared.save(token: response.refresh_token, for: "geogarage_refresh_token")

        // Save username for display
        authService.savedUsername = username

        // Fetch account settings/layers
        let settingsResponse = try await authService.fetchAccountSettings(accessToken: response.access_token)

        self?.availableLayers = settingsResponse.layers
        self?.isAuthorizationReady = true
        self?.forceReauthentication = false

        // Log successful fetch
        let layerNames = settingsResponse.layers.map { $0.brand_name }.joined(separator: ", ")
        Logger.network.info("Successfully fetched layers: \(layerNames, privacy: .public)")
        
        // Clear any previous authentication error messages
        self?.errorMessage = nil
        self?.messageService?.clear(category: .geoGarage)
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
