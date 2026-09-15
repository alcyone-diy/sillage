//
//  GeoGarageAuthService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

@MainActor
protocol GeoGarageAuthServiceProtocol: AnyObject {
  var isGeoGarageAuthenticated: Bool { get }
  var availableLayers: [GeoGarageLayer] { get }
  var authError: Error? { get set }
  var discoverURL: URL? { get }
  var accountManagementURL: URL? { get }
  func bootstrap() async
  /// Authorization code + PKCE sign-in: opens the GeoGarage page via `presenter`, exchanges the
  /// code on /o/token/ and stores both tokens in the Keychain.
  func authenticate(presenter: any GeoGarageAuthorizationPresenting) async throws -> AuthSuccessResponse
  /// Renews the token pair with the refresh token (rotation: it changes on every call).
  func refreshTokens() async throws -> AuthSuccessResponse
  func fetchAccountSettings(accessToken: String) async throws -> GeoGarageSettingsResponse
  func logout() async
}

@Observable
@MainActor
final class GeoGarageAuthService: GeoGarageAuthServiceProtocol {
  var isGeoGarageAuthenticated: Bool = false
  var availableLayers: [GeoGarageLayer] {
    layerRepository.layers
  }

  var authError: Error? = nil
  private var preferencesService: PreferencesServiceProtocol
  private let layerRepository: GeoGarageLayerRepositoryProtocol

  var discoverURL: URL? {
    URL(string: "https://geogarage.com/")
  }
  var accountManagementURL: URL? {
    URL(string: "https://accounts.geogarage.com/")
  }

  private var endpoint: URL? {
    URL(string: "\(AppConstants.GeoGarage.accountsBaseURLString)/o/token/")
  }
  private var settingsEndpoint: URL? {
    URL(string: "\(AppConstants.GeoGarage.accountsBaseURLString)/api/account/settings")
  }

  private let session: URLSession
  @ObservationIgnored private var refreshTask: Task<AuthSuccessResponse, Error>?

  private var authorizeEndpoint: URL? {
    URL(string: "\(AppConstants.GeoGarage.accountsBaseURLString)/o/authorize/")
  }

  init(
    preferencesService: PreferencesServiceProtocol,
    layerRepository: GeoGarageLayerRepositoryProtocol,
    session: URLSession = .shared
  ) {
    self.preferencesService = preferencesService
    self.layerRepository = layerRepository
    self.session = session
  }

  init(preferencesService: PreferencesServiceProtocol, session: URLSession = .shared) {
    self.preferencesService = preferencesService
    self.layerRepository = GeoGarageLayerRepository()
    self.session = session
  }

  func bootstrap() async {
    let hasToken = await Task.detached(priority: .userInitiated) {
      guard let token = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token"),
            !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return false
      }
      return true
    }.value

    self.isGeoGarageAuthenticated = hasToken
    _ = await layerRepository.loadCachedLayers()
  }

  func logout() async {
    // A refresh still in flight would complete after logout, store the new token pair and flip
    // isGeoGarageAuthenticated back on. Cancellation surfaces as AuthError.cancelled.
    refreshTask?.cancel()
    refreshTask = nil
    await KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    await KeychainManager.shared.deleteToken(for: "geogarage_refresh_token")
    // The decryption secret belongs to the session: drop it with the tokens, otherwise another
    // account could reuse it on packages already downloaded.
    await KeychainManager.shared.deleteToken(for: GeoGaragePartnerSecretService.keychainAccount)
    self.authError = nil
    // Installs migrated from the password-based sign-in: the stored username has no further use.
    preferencesService.geoGarageUsername = nil
    self.isGeoGarageAuthenticated = false
    await layerRepository.clearCache()
  }

  // MARK: - Authorization code + PKCE

  func authenticate(presenter: any GeoGarageAuthorizationPresenting) async throws -> AuthSuccessResponse {
    guard let authorizeEndpoint else {
      throw AuthError.invalidResponse
    }
    let verifier = GeoGaragePKCE.makeCodeVerifier()
    let state = GeoGaragePKCE.makeState()
    let authorization = GeoGarageAuthorizationRequest(
      authorizeEndpoint: authorizeEndpoint,
      clientID: AppConfiguration.shared.geoGarageClientID,
      redirectURI: AppConstants.GeoGarage.oauthRedirectURI,
      scope: AppConstants.GeoGarage.oauthScope,
      state: state,
      codeChallenge: GeoGaragePKCE.codeChallenge(for: verifier)
    )
    guard let authorizeURL = authorization.url else {
      throw AuthError.invalidResponse
    }

    let callbackURL: URL
    do {
      callbackURL = try await presenter.authorize(url: authorizeURL, callbackScheme: AppConstants.GeoGarage.oauthCallbackScheme)
    } catch AuthError.cancelled {
      // Deliberate dismissal: leave authError untouched.
      throw AuthError.cancelled
    } catch is CancellationError {
      // The sign-in task itself was cancelled (Cancel button, screen dismissed): a cancellation,
      // not an authorization failure, so no error is surfaced.
      Logger.network.info("GeoGarage authorization cancelled by the caller.")
      throw AuthError.cancelled
    } catch {
      Logger.network.error("Authorization session failed: \(error.localizedDescription, privacy: .public)")
      let failure = AuthError.authorizationFailed(description: error.localizedDescription)
      self.authError = failure
      throw failure
    }

    let code: String
    do {
      code = try GeoGarageAuthorizationRequest.authorizationCode(from: callbackURL, expectedState: state)
    } catch AuthorizationCallbackError.accessDenied {
      let failure = AuthError.accessDenied
      self.authError = failure
      throw failure
    } catch AuthorizationCallbackError.serverError(let description) {
      let failure = AuthError.authorizationFailed(description: description)
      self.authError = failure
      throw failure
    } catch {
      // stateMismatch, missingCode: unusable or forged response, never exchanged.
      Logger.network.error("Authorization callback rejected: \(String(describing: error), privacy: .public)")
      let failure = AuthError.invalidResponse
      self.authError = failure
      throw failure
    }

    do {
      let tokens = try await requestTokens(
        [
          "grant_type": "authorization_code",
          "code": code,
          "redirect_uri": AppConstants.GeoGarage.oauthRedirectURI,
          "client_id": AppConfiguration.shared.geoGarageClientID,
          "code_verifier": verifier,
        ],
        onInvalidGrant: .authorizationFailed(description: "invalid_grant")
      )
      await store(tokens)
      self.authError = nil
      self.isGeoGarageAuthenticated = true
      return tokens
    } catch AuthError.cancelled {
      // Cancelled during the code exchange: silent like the other cancellations, the Settings
      // screen must not display an error.
      throw AuthError.cancelled
    } catch let error as AuthError {
      self.authError = error
      throw error
    }
  }

  func refreshTokens() async throws -> AuthSuccessResponse {
    // The portal rotates refresh tokens: each one is single-use. Concurrent callers (app relaunch,
    // silentlyFetchGeoGarageLayers, packages...) must share a single request, otherwise the second
    // would replay an already-replaced token, get invalid_grant and sign the user out.
    if let running = refreshTask {
      return try await running.value
    }
    let task = Task { @MainActor [weak self] () throws -> AuthSuccessResponse in
      guard let self else { throw AuthError.unknown }
      return try await self.performRefresh()
    }
    refreshTask = task
    defer { refreshTask = nil }
    return try await task.value
  }

  private func performRefresh() async throws -> AuthSuccessResponse {
    guard let refreshToken = await KeychainManager.shared.retrieveToken(for: "geogarage_refresh_token"),
          !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      let failure = AuthError.tokenExpired
      self.authError = failure
      throw failure
    }
    do {
      let tokens = try await requestTokens(
        [
          "grant_type": "refresh_token",
          "refresh_token": refreshToken,
          "client_id": AppConfiguration.shared.geoGarageClientID,
        ],
        onInvalidGrant: .tokenExpired
      )
      await store(tokens)
      self.authError = nil
      self.isGeoGarageAuthenticated = true
      Logger.network.info("GeoGarage tokens refreshed.")
      return tokens
    } catch let error as AuthError {
      switch error {
      case .networkError, .cancelled:
        // Transient network failure (no coverage, tunnel) or cancelled refresh: the session is
        // still valid, do not mark it broken.
        throw error
      default:
        break
      }
      // tokenExpired: refresh token replaced, revoked (password change) or purged after long
      // inactivity, so the user must sign in again. Tokens are kept so the screen shows
      // "Authentication Error" rather than a silently signed-out account. Other failures
      // (invalid_client, 5xx, undecodable response) are published for the same reason: Settings
      // must not report a healthy session while the chart shows an error banner.
      self.authError = error
      throw error
    }
  }

  /// POST /o/token/ (x-www-form-urlencoded). 400/401 with `invalid_grant` → `onInvalidGrant`
  /// (exchange: expired or already-consumed code; refresh: replaced or revoked token);
  /// any other OAuth2 error → `apiError(description:)`.
  private func requestTokens(_ parameters: [String: String], onInvalidGrant: AuthError) async throws -> AuthSuccessResponse {
    guard let endpoint else {
      throw AuthError.invalidResponse
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 15.0 // Marine Context: Fail Fast
    guard let bodyData = encodeParameters(parameters).data(using: .utf8) else {
      throw AuthError.encodingError
    }
    request.httpBody = bodyData

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      // Task cancelled during the exchange: neither a network failure nor an error to display.
      throw AuthError.cancelled
    } catch let error as URLError where error.code == .cancelled {
      // URLSession surfaces Swift task cancellation as URLError.cancelled: same outcome.
      throw AuthError.cancelled
    } catch {
      throw AuthError.networkError(error)
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AuthError.invalidResponse
    }

    switch httpResponse.statusCode {
    case 200:
      do {
        return try JSONDecoder().decode(AuthSuccessResponse.self, from: data)
      } catch {
        Logger.network.error("Failed to decode AuthSuccessResponse: \(error, privacy: .public)")
        throw AuthError.invalidResponse
      }
    case 400, 401:
      let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
      if errorResponse?.error == "invalid_grant" {
        throw onInvalidGrant
      }
      if let description = errorResponse?.error_description, !description.isEmpty {
        throw AuthError.apiError(description: description)
      }
      if let code = errorResponse?.error, !code.isEmpty {
        throw AuthError.apiError(description: code)
      }
      throw AuthError.unknown
    default:
      throw AuthError.invalidResponse
    }
  }

  private func store(_ tokens: AuthSuccessResponse) async {
    await KeychainManager.shared.save(token: tokens.access_token, for: "geogarage_access_token")
    await KeychainManager.shared.save(token: tokens.refresh_token, for: "geogarage_refresh_token")
  }

  func fetchAccountSettings(accessToken: String) async throws -> GeoGarageSettingsResponse {
    do {
      return try await performFetchAccountSettings(accessToken: accessToken)
    } catch AuthError.tokenExpired {
      // The 24 h access token expired. With PKCE the app holds no password to sign in again:
      // refresh silently with the refresh token and retry once. If the refresh fails, tokenExpired
      // propagates and the screen asks the user to sign in again.
      let refreshed = try await refreshTokens()
      return try await performFetchAccountSettings(accessToken: refreshed.access_token)
    }
  }

  private func performFetchAccountSettings(accessToken: String) async throws -> GeoGarageSettingsResponse {
    guard let settingsEndpoint else {
      throw AuthError.invalidResponse
    }

    var request = URLRequest(url: settingsEndpoint)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 15.0

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      let cached = layerRepository.layers
      if !cached.isEmpty {
        let customerID = preferencesService.geoGarageCustomerID ?? ""
        return GeoGarageSettingsResponse(customerID: customerID, layers: cached)
      }
      throw AuthError.networkError(error)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw AuthError.invalidResponse
    }

    if httpResponse.statusCode == 200 {
      do {
        let settingsResponse = try JSONDecoder().decode(GeoGarageSettingsResponse.self, from: data)
        self.authError = nil
        // Persist customerID — non-sensitive, used to build the SQLCipher decryption key at runtime.
        preferencesService.geoGarageCustomerID = settingsResponse.customerID
        Logger.network.debug("GeoGarage customerID captured from settings response.")
        await layerRepository.saveLayers(settingsResponse.layers)
        return settingsResponse
      } catch {
        Logger.network.error("Failed to decode GeoGarageSettingsResponse: \(error, privacy: .public)")
        throw AuthError.invalidResponse
      }
    } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
      // The portal answers 403 to an expired or invalid Bearer token; without this case the silent
      // refresh never triggered and the user had to sign in again every day. 401 is kept as well in
      // case the portal switches to the standard response.
      let error = AuthError.tokenExpired
      self.authError = error
      throw error
    } else {
      let error = AuthError.fetchSettingsFailed(statusCode: httpResponse.statusCode)
      self.authError = error
      throw error
    }
  }

  /// Robustly encodes dictionary parameters into an x-www-form-urlencoded string.
  private func encodeParameters(_ parameters: [String: String]) -> String {
    return parameters.map { key, value in
      let escapedKey = escape(key)
      let escapedValue = escape(value)
      return "\(escapedKey)=\(escapedValue)"
    }.joined(separator: "&")
  }

  /// Custom URL encoding for x-www-form-urlencoded that safely escapes special characters.
  private func escape(_ string: String) -> String {
    // x-www-form-urlencoded requires more aggressive encoding than .urlQueryAllowed
    // Specifically, we must ensure characters like +, &, =, and / are properly encoded.
    var allowedCharacters = CharacterSet.alphanumerics
    allowedCharacters.insert(charactersIn: "-._~") // Unreserved characters per RFC 3986

    return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
  }
}
