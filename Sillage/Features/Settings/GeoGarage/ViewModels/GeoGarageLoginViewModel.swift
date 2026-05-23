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
  var errorMessage: String? = nil
  var availableLayers: [GeoGarageLayer] = []
  var isAuthorizationReady: Bool = false

  private let authService: GeoGarageAuthServiceProtocol

  @MainActor
  init(authService: GeoGarageAuthServiceProtocol? = nil) {
    self.authService = authService ?? GeoGarageAuthService()
  }

  func login() {
    Task {
      isLoading = true
      errorMessage = nil

      defer { isLoading = false }

      if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        errorMessage = String(localized: "Please enter a valid username.")
        return
      }

      do {
        let response = try await authService.authenticate(username: username, password: password)

        // Save tokens securely
        KeychainManager.shared.save(token: response.access_token, for: "geogarage_access_token")
        KeychainManager.shared.save(token: response.refresh_token, for: "geogarage_refresh_token")

        // Fetch account settings/layers
        let settingsResponse = try await authService.fetchAccountSettings(accessToken: response.access_token)

        // Ensure UI-bound updates are explicitly on the MainActor
        await MainActor.run {
          availableLayers = settingsResponse.layers
          isAuthorizationReady = true
        }

        // Log successful fetch
        let layerNames = settingsResponse.layers.map { $0.brand_name }.joined(separator: ", ")
        Logger.network.info("Successfully fetched layers: \(layerNames, privacy: .public)")
      } catch let error as AuthError {
        errorMessage = error.localizedDescription
      } catch {
        errorMessage = AuthError.unknown.localizedDescription
      }
    }
  }
}
