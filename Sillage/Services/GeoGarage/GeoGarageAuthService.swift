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
  var savedUsername: String? { get set }
  var discoverURL: URL? { get }
  var accountManagementURL: URL? { get }
  func bootstrap() async
  func authenticate(username: String, password: String) async throws -> AuthSuccessResponse
  /// Connexion authorization code + PKCE : ouvre la page GeoGarage via `presenter`, échange le
  /// code sur /o/token/ et range les deux tokens dans le trousseau.
  func authenticate(presenter: any GeoGarageAuthorizationPresenting) async throws -> AuthSuccessResponse
  /// Renouvelle la paire de tokens avec le refresh token (rotation : il change à chaque appel).
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
  
  var savedUsername: String? {
    get { preferencesService.geoGarageUsername }
    set { preferencesService.geoGarageUsername = newValue }
  }

  var discoverURL: URL? {
    URL(string: "https://geogarage.com/")
  }
  var accountManagementURL: URL? {
    URL(string: "https://accounts.geogarage.com/")
  }

  private var endpoint: URL? {
    URL(string: "https://accounts.geogarage.com/o/token/")
  }
  private var settingsEndpoint: URL? {
    URL(string: "https://accounts.geogarage.com/api/account/settings")
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
    await KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    await KeychainManager.shared.deleteToken(for: "geogarage_refresh_token")
    self.authError = nil
    self.savedUsername = nil
    self.isGeoGarageAuthenticated = false
    await layerRepository.clearCache()
  }

  func authenticate(username: String, password: String) async throws -> AuthSuccessResponse {
    guard let endpoint else {
      throw AuthError.invalidResponse
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 15.0 // Marine Context: Fail Fast

    let parameters: [String: String] = [
      "grant_type": "password",
      "client_id": AppConfiguration.shared.geoGarageClientID,
      "username": username,
      "password": password
    ]

    let bodyString = encodeParameters(parameters)
    guard let bodyData = bodyString.data(using: .utf8) else {
      throw AuthError.encodingError
    }
    request.httpBody = bodyData

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw AuthError.networkError(error)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw AuthError.invalidResponse
    }

    if httpResponse.statusCode == 200 {
      do {
        let successResponse = try JSONDecoder().decode(AuthSuccessResponse.self, from: data)
        self.authError = nil
        self.isGeoGarageAuthenticated = true
        return successResponse
      } catch {
        Logger.network.error("Failed to decode AuthSuccessResponse: \(error, privacy: .public)")
        throw AuthError.invalidResponse
      }
    } else if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
      if let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data) {
        if errorResponse.error == "invalid_grant" {
          let error = AuthError.invalidCredentials
          self.authError = error
          throw error
        }
        if let description = errorResponse.error_description, !description.isEmpty {
          let error = AuthError.apiError(description: description)
          self.authError = error
          throw error
        }
      }
      throw AuthError.unknown
    } else {
      throw AuthError.invalidResponse
    }
  }

  // MARK: - Authorization code + PKCE (11 sept. 2026)

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
      // Fermeture volontaire : on ne touche pas à authError, l'écran reste tel quel.
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
      // stateMismatch, missingCode : réponse inexploitable ou forgée, jamais échangée.
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
    } catch let error as AuthError {
      self.authError = error
      throw error
    }
  }

  func refreshTokens() async throws -> AuthSuccessResponse {
    // Rotation côté portail : un refresh token ne sert qu'une fois. Deux appels concurrents
    // (relance de l'app, silentlyFetchGeoGarageLayers, paquets…) partagent donc une seule requête ;
    // sinon le second rejouerait un token déjà remplacé, recevrait invalid_grant et déconnecterait
    // l'utilisateur (constaté en conception le 11 sept. 2026, test testConcurrentRefreshesShareASingleRequest).
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
    } catch AuthError.tokenExpired {
      // Refresh token remplacé, révoqué (changement de mot de passe) ou purgé (deux ans sans usage) :
      // il faut repasser par la page GeoGarage. Les tokens restent en place pour que l'écran montre
      // « Authentication Error » plutôt qu'un compte déconnecté sans explication.
      self.authError = AuthError.tokenExpired
      throw AuthError.tokenExpired
    }
  }

  /// POST /o/token/ (x-www-form-urlencoded). 400/401 avec `invalid_grant` → `onInvalidGrant`
  /// (à l'échange : code périmé ou déjà consommé ; au refresh : token remplacé ou révoqué) ;
  /// autre erreur OAuth2 → `apiError(description:)`.
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
      // Access token de 24 h périmé. Depuis le passage en PKCE (11 sept. 2026) l'app n'a plus de mot
      // de passe pour se reconnecter : on renouvelle en silence avec le refresh token et on rejoue une
      // seule fois. Si le refresh échoue, tokenExpired remonte et l'écran demande de se reconnecter.
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
    } else if httpResponse.statusCode == 401 {
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
