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
import Observation
@testable import Sillage

@Observable
final class MockGeoGarageAuthService: GeoGarageAuthServiceProtocol, @unchecked Sendable {
  var isGeoGarageAuthenticated: Bool = false
  var availableLayers: [GeoGarageLayer] = []
  var authError: Error?
  var discoverURL: URL? { URL(string: "https://geogarage.com/") }
  var accountManagementURL: URL? { URL(string: "https://accounts.geogarage.com/") }
  var shouldFailAuthenticate = false
  var authErrorToThrow: AuthError?
  var shouldFailFetchAccountSettings = false
  var shouldFailWithNetworkError = false
  var refreshErrorToThrow: AuthError?
  private(set) var lastPresenter: (any GeoGarageAuthorizationPresenting)?
  /// Number of authorization page openings: a double tap must produce a single one.
  private(set) var authenticateCallCount = 0
  /// Holds `authenticate` until `releaseAuthenticate()` so a second call can be made while the
  /// first is still in flight.
  var holdsAuthenticate = false
  private var authenticateReleased = false
  private var authenticateWaiters: [CheckedContinuation<Void, Never>] = []

  func releaseAuthenticate() {
    authenticateReleased = true
    let waiters = authenticateWaiters
    authenticateWaiters = []
    for waiter in waiters {
      waiter.resume()
    }
  }

  func bootstrap() async {
    // Mock bootstrap
  }

  func authenticate(presenter: any GeoGarageAuthorizationPresenting) async throws -> AuthSuccessResponse {
    lastPresenter = presenter
    authenticateCallCount += 1
    if holdsAuthenticate, !authenticateReleased {
      await withCheckedContinuation { continuation in
        authenticateWaiters.append(continuation)
      }
    }
    if let error = authErrorToThrow {
      throw error
    }
    if shouldFailAuthenticate {
      throw AuthError.invalidResponse
    }
    isGeoGarageAuthenticated = true
    return AuthSuccessResponse(access_token: "mock_access", token_type: "Bearer", expires_in: 3600, refresh_token: "mock_refresh", scope: "write read")
  }

  func refreshTokens() async throws -> AuthSuccessResponse {
    if let error = refreshErrorToThrow {
      throw error
    }
    return AuthSuccessResponse(access_token: "mock_access_2", token_type: "Bearer", expires_in: 3600, refresh_token: "mock_refresh_2", scope: "write read")
  }

  func fetchAccountSettings(accessToken: String) async throws -> GeoGarageSettingsResponse {
    if shouldFailWithNetworkError {
      if !availableLayers.isEmpty {
        return GeoGarageSettingsResponse(customerID: "cus_mock123", layers: availableLayers)
      }
      throw AuthError.networkError(NSError(domain: "Network", code: -1009, userInfo: nil))
    }
    if shouldFailFetchAccountSettings {
      throw AuthError.tokenExpired
    }
    return GeoGarageSettingsResponse(customerID: "cus_mock123", layers: availableLayers)
  }

  func logout() async {
    await KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    await KeychainManager.shared.deleteToken(for: "geogarage_refresh_token")
    await KeychainManager.shared.deleteToken(for: GeoGaragePartnerSecretService.keychainAccount)
    self.authError = nil
    self.isGeoGarageAuthenticated = false
    self.availableLayers = []
  }
}
