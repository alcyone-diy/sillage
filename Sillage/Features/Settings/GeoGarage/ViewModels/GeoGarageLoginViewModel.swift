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

@MainActor
@Observable
final class GeoGarageLoginViewModel {
  var username = ""
  var password = ""
  var isLoading = false
  var availableLayers: [GeoGarageLayer] = []
  var isAuthorizationReady: Bool = false

  var errorMessage: String?

  private let authService: GeoGarageAuthServiceProtocol
  var loginTask: Task<Void, Never>?

  init(authService: GeoGarageAuthServiceProtocol? = nil) {
    self.authService = authService ?? GeoGarageAuthService()
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

        // Fetch account settings/layers
        let settingsResponse = try await authService.fetchAccountSettings(accessToken: response.access_token)

        self?.availableLayers = settingsResponse.layers
        self?.isAuthorizationReady = true

        // Log successful fetch
        let layerNames = settingsResponse.layers.map { $0.brand_name }.joined(separator: ", ")
        Logger.network.info("Successfully fetched layers: \(layerNames, privacy: .public)")
        
        // Clear any previous authentication error messages
        self?.errorMessage = nil
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
