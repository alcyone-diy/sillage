//
//  GeoGarageLoginViewModel.swift
//  Alcyone Sillage
//
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
@Observable
final class GeoGarageLoginViewModel {
  var username = ""
  var password = ""
  var isLoading = false
  var errorMessage: String? = nil

  private let authService: GeoGarageAuthServiceProtocol

  init(authService: GeoGarageAuthServiceProtocol = GeoGarageAuthService()) {
    self.authService = authService
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
        print("\n--- SUCCESS: Access Token: \(response.access_token) ---\n")
      } catch let error as AuthError {
        errorMessage = error.localizedDescription
      } catch {
        errorMessage = AuthError.unknown.localizedDescription
      }
    }
  }
}
