//
//  GeoGarageAuthServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import os
@testable import Sillage

/// Journal des requêtes vues par MockURLProtocol (le handler s'exécute hors du MainActor).
private final class RequestLog: @unchecked Sendable {
  private let lock = OSAllocatedUnfairLock(initialState: [URLRequest]())
  func append(_ request: URLRequest) { lock.withLock { $0.append(request) } }
  var requests: [URLRequest] { lock.withLock { $0 } }
}

@MainActor
final class GeoGarageAuthServiceTests: XCTestCase {

  private let tokenJSON = #"{"access_token":"new-access","token_type":"Bearer","expires_in":86400,"refresh_token":"new-refresh","scope":"write read"}"#
  private let settingsJSON = #"{"customer_id":"cus_42","layers":[{"layer":"shom","brand_name":"SHOM","version_date":"2026-01-01","valid_until":"2027-01-01"}]}"#

  private var session: URLSession!
  private var service: GeoGarageAuthService!
  private var presenter: MockGeoGarageAuthorizationPresenter!

  override func setUp() async throws {
    try await super.setUp()
    MockURLProtocol.reset()
    session = MockURLProtocol.makeMockSession()
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("layers-\(UUID().uuidString).json")
    service = GeoGarageAuthService(
      preferencesService: PreferencesService(),
      layerRepository: GeoGarageLayerRepository(cacheFileURL: cacheURL),
      session: session
    )
    presenter = MockGeoGarageAuthorizationPresenter()
    await KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    await KeychainManager.shared.deleteToken(for: "geogarage_refresh_token")
    await KeychainManager.shared.deleteToken(for: GeoGaragePartnerSecretService.keychainAccount)
  }

  override func tearDown() async throws {
    await KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    await KeychainManager.shared.deleteToken(for: "geogarage_refresh_token")
    await KeychainManager.shared.deleteToken(for: GeoGaragePartnerSecretService.keychainAccount)
    MockURLProtocol.reset()
    service = nil
    session = nil
    presenter = nil
    try await super.tearDown()
  }

  // MARK: - Helpers

  private static func response(_ request: URLRequest, status: Int) -> HTTPURLResponse {
    let url = request.url ?? URL(fileURLWithPath: "/")
    return HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) ?? HTTPURLResponse()
  }

  /// Corps x-www-form-urlencoded d'une requête interceptée. URLSession ne transmet le corps à un
  /// URLProtocol que sous forme de flux (`httpBodyStream`), jamais dans `httpBody`.
  private static func formBody(of request: URLRequest) -> [String: String] {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        guard read > 0 else { break }
        data.append(buffer, count: read)
      }
    }
    guard let body = String(data: data, encoding: .utf8) else { return [:] }
    var result: [String: String] = [:]
    for pair in body.split(separator: "&") {
      let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { continue }
      result[parts[0].removingPercentEncoding ?? parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
    }
    return result
  }

  /// Handler unique : /o/token/ répond des tokens, /api/account/settings exige "Bearer new-access".
  private func installPortalHandler(tokenStatus: Int = 200, tokenBody: String? = nil, log: RequestLog) {
    let tokenJSON = self.tokenJSON
    let settingsJSON = self.settingsJSON
    MockURLProtocol.setHandler { request in
      log.append(request)
      switch request.url?.path {
      case "/o/token":  // URL.path retire le "/" final
        return (Self.response(request, status: tokenStatus), Data((tokenBody ?? tokenJSON).utf8))
      case "/api/account/settings":
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access" {
          return (Self.response(request, status: 200), Data(settingsJSON.utf8))
        }
        return (Self.response(request, status: 401), Data())
      default:
        return (Self.response(request, status: 404), Data())
      }
    }
  }

  // MARK: - authenticate(presenter:)

  func testAuthenticateExchangesCodeWithPKCEAndStoresTokens() async throws {
    let log = RequestLog()
    installPortalHandler(log: log)

    let tokens = try await service.authenticate(presenter: presenter)

    XCTAssertEqual(tokens.access_token, "new-access")
    XCTAssertEqual(presenter.lastCallbackScheme, "com.alcyone-sillage.app")
    let authorizeURL = try XCTUnwrap(presenter.lastAuthorizeURL)
    XCTAssertEqual(authorizeURL.path, "/o/authorize")  // URL.path retire le "/" final
    let authorizeQuery = Dictionary(uniqueKeysWithValues: (URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    XCTAssertEqual(authorizeQuery["code_challenge_method"], "S256")
    XCTAssertEqual(authorizeQuery["redirect_uri"], "com.alcyone-sillage.app://oauth2/callback")

    let tokenRequest = try XCTUnwrap(log.requests.first { $0.url?.path == "/o/token" })
    XCTAssertEqual(tokenRequest.httpMethod, "POST")
    let body = Self.formBody(of: tokenRequest)
    XCTAssertEqual(body["grant_type"], "authorization_code")
    XCTAssertEqual(body["code"], "code-123")
    XCTAssertEqual(body["redirect_uri"], "com.alcyone-sillage.app://oauth2/callback")
    XCTAssertEqual(body["client_id"], AppConfiguration.shared.geoGarageClientID)
    let verifier = try XCTUnwrap(body["code_verifier"])
    XCTAssertEqual(GeoGaragePKCE.codeChallenge(for: verifier), authorizeQuery["code_challenge"], "le code_verifier envoyé doit correspondre au code_challenge de l'autorisation")

    let storedAccess = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token")
    let storedRefresh = await KeychainManager.shared.retrieveToken(for: "geogarage_refresh_token")
    XCTAssertEqual(storedAccess, "new-access")
    XCTAssertEqual(storedRefresh, "new-refresh")
    XCTAssertTrue(service.isGeoGarageAuthenticated)
    XCTAssertNil(service.authError)
  }

  func testAuthenticateReportsAccessDeniedWithoutCallingTokenEndpoint() async {
    let log = RequestLog()
    installPortalHandler(log: log)
    presenter.behaviour = .returnQuery("error=access_denied")

    do {
      _ = try await service.authenticate(presenter: presenter)
      XCTFail("accessDenied attendu")
    } catch AuthError.accessDenied {
      // attendu
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
    XCTAssertTrue(log.requests.isEmpty)
    XCTAssertFalse(service.isGeoGarageAuthenticated)
    let storedAccess = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token")
    XCTAssertNil(storedAccess)
  }

  func testAuthenticateRejectsCallbackWithWrongState() async throws {
    let log = RequestLog()
    installPortalHandler(log: log)
    presenter.behaviour = .returnRawCallback(try XCTUnwrap(URL(string: "com.alcyone-sillage.app://oauth2/callback?code=stolen&state=forged")))

    do {
      _ = try await service.authenticate(presenter: presenter)
      XCTFail("invalidResponse attendu")
    } catch AuthError.invalidResponse {
      // attendu
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
    XCTAssertTrue(log.requests.isEmpty, "un code au mauvais state ne doit jamais être échangé")
  }

  func testAuthenticateLetsCancellationThroughWithoutError() async {
    presenter.behaviour = .throwError(AuthError.cancelled)

    do {
      _ = try await service.authenticate(presenter: presenter)
      XCTFail("cancelled attendu")
    } catch AuthError.cancelled {
      // attendu
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
    XCTAssertNil(service.authError, "une annulation n'est pas une erreur à afficher")
    XCTAssertFalse(service.isGeoGarageAuthenticated)
  }

  func testAuthenticateTreatsTaskCancellationAsCancelled() async {
    let log = RequestLog()
    installPortalHandler(log: log)
    presenter.behaviour = .throwError(CancellationError())

    do {
      _ = try await service.authenticate(presenter: presenter)
      XCTFail("cancelled attendu")
    } catch AuthError.cancelled {
      // attendu : annuler la tâche de connexion n'est pas un échec d'autorisation
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
    XCTAssertNil(service.authError, "une annulation de tâche n'est pas une erreur à afficher")
    XCTAssertTrue(log.requests.isEmpty, "rien à échanger après une annulation")
    XCTAssertFalse(service.isGeoGarageAuthenticated)
  }

  func testAuthenticateMapsInvalidGrantToAuthorizationFailed() async {
    let log = RequestLog()
    installPortalHandler(tokenStatus: 400, tokenBody: #"{"error": "invalid_grant"}"#, log: log)

    do {
      _ = try await service.authenticate(presenter: presenter)
      XCTFail("authorizationFailed attendu")
    } catch AuthError.authorizationFailed {
      // attendu : code périmé (60 s) ou déjà consommé
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
    XCTAssertNotNil(service.authError)
    XCTAssertFalse(service.isGeoGarageAuthenticated)
  }

  // MARK: - refreshTokens()

  func testRefreshTokensRotatesAndStoresTheNewPair() async throws {
    await KeychainManager.shared.save(token: "old-access", for: "geogarage_access_token")
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    installPortalHandler(log: log)

    let tokens = try await service.refreshTokens()

    XCTAssertEqual(tokens.refresh_token, "new-refresh")
    let tokenRequest = try XCTUnwrap(log.requests.first)
    let body = Self.formBody(of: tokenRequest)
    XCTAssertEqual(body["grant_type"], "refresh_token")
    XCTAssertEqual(body["refresh_token"], "old-refresh")
    XCTAssertEqual(body["client_id"], AppConfiguration.shared.geoGarageClientID)
    XCTAssertNil(body["client_secret"], "client public : jamais de secret")
    let storedAccess = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token")
    let storedRefresh = await KeychainManager.shared.retrieveToken(for: "geogarage_refresh_token")
    XCTAssertEqual(storedAccess, "new-access")
    XCTAssertEqual(storedRefresh, "new-refresh")
  }

  func testRefreshTokensWithInvalidGrantThrowsTokenExpired() async {
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    installPortalHandler(tokenStatus: 400, tokenBody: #"{"error": "invalid_grant"}"#, log: log)

    do {
      _ = try await service.refreshTokens()
      XCTFail("tokenExpired attendu")
    } catch AuthError.tokenExpired {
      // attendu : refresh token remplacé (rotation), révoqué ou purgé
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
    XCTAssertNotNil(service.authError)
  }

  func testRefreshTokensPublishesAuthErrorForInvalidClient() async {
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    installPortalHandler(tokenStatus: 400, tokenBody: #"{"error": "invalid_client"}"#, log: log)

    do {
      _ = try await service.refreshTokens()
      XCTFail("apiError attendu")
    } catch AuthError.apiError(let description) {
      XCTAssertEqual(description, "invalid_client")
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
    XCTAssertNotNil(service.authError, "un refresh en échec autre qu'invalid_grant doit aussi être publié")
  }

  func testRefreshTokensKeepsAuthErrorNilWhenOffline() async {
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    MockURLProtocol.setErrorHandler { request in
      guard request.url?.path == "/o/token" else { return nil }
      return URLError(.notConnectedToInternet)
    }

    do {
      _ = try await service.refreshTokens()
      XCTFail("networkError attendu")
    } catch AuthError.networkError {
      // attendu
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
    XCTAssertNil(service.authError, "une panne réseau passagère ne doit pas marquer la session cassée")
  }

  func testRefreshTokensWithoutStoredRefreshTokenThrowsTokenExpired() async {
    let log = RequestLog()
    installPortalHandler(log: log)

    do {
      _ = try await service.refreshTokens()
      XCTFail("tokenExpired attendu")
    } catch AuthError.tokenExpired {
      // attendu
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
    XCTAssertTrue(log.requests.isEmpty)
  }

  func testConcurrentRefreshesShareASingleRequest() async throws {
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    installPortalHandler(log: log)

    async let first = service.refreshTokens()
    async let second = service.refreshTokens()
    let (a, b) = try await (first, second)

    XCTAssertEqual(a.refresh_token, b.refresh_token)
    XCTAssertEqual(log.requests.filter { $0.url?.path == "/o/token" }.count, 1, "la rotation interdit deux refreshs avec le même token")
  }

  func testSequentialRefreshesIssueTwoRequests() async throws {
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    installPortalHandler(log: log)

    _ = try await service.refreshTokens()
    _ = try await service.refreshTokens()

    let tokenRequests = log.requests.filter { $0.url?.path == "/o/token" }
    XCTAssertEqual(tokenRequests.count, 2, "refreshTask doit être libéré après chaque refresh")
    let second = try XCTUnwrap(tokenRequests.dropFirst().first)
    XCTAssertEqual(Self.formBody(of: second)["refresh_token"], "new-refresh", "le second refresh rejoue le token renvoyé par le premier (rotation)")
  }

  // MARK: - fetchAccountSettings(accessToken:) et 401

  func testFetchAccountSettingsRefreshesOnceOn401ThenRetries() async throws {
    await KeychainManager.shared.save(token: "old-access", for: "geogarage_access_token")
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    installPortalHandler(log: log)

    let settings = try await service.fetchAccountSettings(accessToken: "old-access")

    XCTAssertEqual(settings.customerID, "cus_42")
    XCTAssertEqual(settings.layers.map(\.layer), ["shom"])
    let paths = log.requests.map { $0.url?.path ?? "" }
    XCTAssertEqual(paths, ["/api/account/settings", "/o/token", "/api/account/settings"])
    XCTAssertEqual(log.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
    XCTAssertNil(service.authError)
  }

  func testFetchAccountSettingsThrowsTokenExpiredWhenRefreshFails() async {
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    installPortalHandler(tokenStatus: 400, tokenBody: #"{"error": "invalid_grant"}"#, log: log)

    do {
      _ = try await service.fetchAccountSettings(accessToken: "old-access")
      XCTFail("tokenExpired attendu")
    } catch AuthError.tokenExpired {
      // attendu
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
    let paths = log.requests.map { $0.url?.path ?? "" }
    XCTAssertEqual(paths, ["/api/account/settings", "/o/token"], "un seul essai de refresh, pas de boucle")
  }

  // MARK: - Déconnexion

  func testLogoutRemovesPackageSecret() async {
    await KeychainManager.shared.save(token: "access", for: "geogarage_access_token")
    await KeychainManager.shared.save(token: "s3cret", for: GeoGaragePartnerSecretService.keychainAccount)

    await service.logout()

    let secret = await KeychainManager.shared.retrieveToken(for: GeoGaragePartnerSecretService.keychainAccount)
    XCTAssertNil(secret, "le secret de déchiffrement part avec la session")
    let access = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token")
    XCTAssertNil(access)
  }
}
