//
//  MockGeoGarageAuthService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
@testable import Sillage

final class MockGeoGarageAuthService: GeoGarageAuthServiceProtocol, @unchecked Sendable {
  var authError: Error?
  var shouldFailAuthenticate = false
  var shouldFailFetchAccountSettings = false
  var shouldFailWithNetworkError = false

  func authenticate(username: String, password: String) async throws -> AuthSuccessResponse {
    if shouldFailAuthenticate {
      throw AuthError.invalidResponse
    }
    return AuthSuccessResponse(access_token: "mock_access", token_type: "Bearer", expires_in: 3600, refresh_token: "mock_refresh", scope: "read")
  }

  func fetchAccountSettings(accessToken: String) async throws -> GeoGarageSettingsResponse {
    if shouldFailWithNetworkError {
      throw AuthError.networkError(NSError(domain: "Network", code: -1009, userInfo: nil))
    }
    if shouldFailFetchAccountSettings {
      throw AuthError.tokenExpired
    }
    return GeoGarageSettingsResponse(layers: [])
  }

  func logout() {
    KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    KeychainManager.shared.deleteToken(for: "geogarage_refresh_token")
    self.authError = nil
  }
}
