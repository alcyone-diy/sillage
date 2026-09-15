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

/// Log of the requests seen by `MockURLProtocol` (the handler runs off the MainActor).
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

  /// x-www-form-urlencoded body of an intercepted request. URLSession only hands the body to a
  /// URLProtocol as a stream (`httpBodyStream`), never in `httpBody`.
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

  /// Single handler: /o/token/ returns tokens, /api/account/settings requires "Bearer new-access".
  /// `rejectedStatus` is the code returned for a stale Bearer: the real portal answers 403, 401 is
  /// covered as well.
  private func installPortalHandler(
    tokenStatus: Int = 200,
    tokenBody: String? = nil,
    rejectedStatus: Int = 401,
    log: RequestLog
  ) {
    let tokenJSON = self.tokenJSON
    let settingsJSON = self.settingsJSON
    MockURLProtocol.setHandler { request in
      log.append(request)
      switch request.url?.path {
      case "/o/token":  // URL.path drops the trailing "/"
        return (Self.response(request, status: tokenStatus), Data((tokenBody ?? tokenJSON).utf8))
      case "/api/account/settings":
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access" {
          return (Self.response(request, status: 200), Data(settingsJSON.utf8))
        }
        return (Self.response(request, status: rejectedStatus), Data())
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
    XCTAssertEqual(authorizeURL.path, "/o/authorize")  // URL.path drops the trailing "/"
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
    XCTAssertEqual(GeoGaragePKCE.codeChallenge(for: verifier), authorizeQuery["code_challenge"], "the code_verifier sent must match the authorization code_challenge")

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
      XCTFail("expected accessDenied")
    } catch AuthError.accessDenied {
      // expected
    } catch {
      XCTFail("unexpected error: \(error)")
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
      XCTFail("expected invalidResponse")
    } catch AuthError.invalidResponse {
      // expected
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    XCTAssertTrue(log.requests.isEmpty, "a code with a wrong state must never be exchanged")
  }

  func testAuthenticateLetsCancellationThroughWithoutError() async {
    presenter.behaviour = .throwError(AuthError.cancelled)

    do {
      _ = try await service.authenticate(presenter: presenter)
      XCTFail("expected cancelled")
    } catch AuthError.cancelled {
      // expected
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    XCTAssertNil(service.authError, "a cancellation is not an error to display")
    XCTAssertFalse(service.isGeoGarageAuthenticated)
  }

  func testAuthenticateTreatsTaskCancellationAsCancelled() async {
    let log = RequestLog()
    installPortalHandler(log: log)
    presenter.behaviour = .throwError(CancellationError())

    do {
      _ = try await service.authenticate(presenter: presenter)
      XCTFail("expected cancelled")
    } catch AuthError.cancelled {
      // expected: cancelling the sign-in task is not an authorization failure
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    XCTAssertNil(service.authError, "a task cancellation is not an error to display")
    XCTAssertTrue(log.requests.isEmpty, "nothing to exchange after a cancellation")
    XCTAssertFalse(service.isGeoGarageAuthenticated)
  }

  func testAuthenticateMapsInvalidGrantToAuthorizationFailed() async {
    let log = RequestLog()
    installPortalHandler(tokenStatus: 400, tokenBody: #"{"error": "invalid_grant"}"#, log: log)

    do {
      _ = try await service.authenticate(presenter: presenter)
      XCTFail("expected authorizationFailed")
    } catch AuthError.authorizationFailed {
      // expected: code expired (60 s) or already used
    } catch {
      XCTFail("unexpected error: \(error)")
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
    XCTAssertNil(body["client_secret"], "public client: never a secret")
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
      XCTFail("expected tokenExpired")
    } catch AuthError.tokenExpired {
      // expected: refresh token rotated, revoked or purged
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    XCTAssertNotNil(service.authError)
  }

  func testRefreshTokensPublishesAuthErrorForInvalidClient() async {
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    installPortalHandler(tokenStatus: 400, tokenBody: #"{"error": "invalid_client"}"#, log: log)

    do {
      _ = try await service.refreshTokens()
      XCTFail("expected apiError")
    } catch AuthError.apiError(let description) {
      XCTAssertEqual(description, "invalid_client")
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    XCTAssertNotNil(service.authError, "a refresh failure other than invalid_grant must be published too")
  }

  func testRefreshTokensKeepsAuthErrorNilWhenOffline() async {
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    MockURLProtocol.setErrorHandler { request in
      guard request.url?.path == "/o/token" else { return nil }
      return URLError(.notConnectedToInternet)
    }

    do {
      _ = try await service.refreshTokens()
      XCTFail("expected networkError")
    } catch AuthError.networkError {
      // expected
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    XCTAssertNil(service.authError, "a transient network failure must not mark the session as broken")
  }

  func testRefreshTokensWithoutStoredRefreshTokenThrowsTokenExpired() async {
    let log = RequestLog()
    installPortalHandler(log: log)

    do {
      _ = try await service.refreshTokens()
      XCTFail("expected tokenExpired")
    } catch AuthError.tokenExpired {
      // expected
    } catch {
      XCTFail("unexpected error: \(error)")
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
    XCTAssertEqual(log.requests.filter { $0.url?.path == "/o/token" }.count, 1, "rotation forbids two refreshes with the same token")
  }

  func testSequentialRefreshesIssueTwoRequests() async throws {
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    installPortalHandler(log: log)

    _ = try await service.refreshTokens()
    _ = try await service.refreshTokens()

    let tokenRequests = log.requests.filter { $0.url?.path == "/o/token" }
    XCTAssertEqual(tokenRequests.count, 2, "refreshTask must be released after each refresh")
    let second = try XCTUnwrap(tokenRequests.dropFirst().first)
    XCTAssertEqual(Self.formBody(of: second)["refresh_token"], "new-refresh", "the second refresh replays the token returned by the first (rotation)")
  }

  // MARK: - fetchAccountSettings(accessToken:) and 401/403

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
      XCTFail("expected tokenExpired")
    } catch AuthError.tokenExpired {
      // expected
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    let paths = log.requests.map { $0.url?.path ?? "" }
    XCTAssertEqual(paths, ["/api/account/settings", "/o/token"], "a single refresh attempt, no loop")
  }

  /// The portal answers 403 (not 401) to a stale Bearer: without this case the silent refresh never
  /// fired and the user had to sign in again every day.
  func testFetchAccountSettingsRefreshesOnceOn403ThenRetries() async throws {
    await KeychainManager.shared.save(token: "old-access", for: "geogarage_access_token")
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    installPortalHandler(rejectedStatus: 403, log: log)

    let settings = try await service.fetchAccountSettings(accessToken: "old-access")

    XCTAssertEqual(settings.customerID, "cus_42")
    XCTAssertEqual(settings.layers.map(\.layer), ["shom"])
    let paths = log.requests.map { $0.url?.path ?? "" }
    XCTAssertEqual(paths, ["/api/account/settings", "/o/token", "/api/account/settings"])
    XCTAssertEqual(log.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
    XCTAssertNil(service.authError)
  }

  func testFetchAccountSettingsThrowsTokenExpiredWhenRefreshFailsAfterA403() async {
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    installPortalHandler(tokenStatus: 400, tokenBody: #"{"error": "invalid_grant"}"#, rejectedStatus: 403, log: log)

    do {
      _ = try await service.fetchAccountSettings(accessToken: "old-access")
      XCTFail("expected tokenExpired")
    } catch AuthError.tokenExpired {
      // expected
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    let paths = log.requests.map { $0.url?.path ?? "" }
    XCTAssertEqual(paths, ["/api/account/settings", "/o/token"], "a single refresh attempt, no loop")
  }

  // MARK: - Logout

  /// A refresh started right before "Log Out" could complete after it, rewrite the tokens in the
  /// Keychain and turn `isGeoGarageAuthenticated` back on.
  func testLogoutCancelsAnInFlightRefresh() async throws {
    await KeychainManager.shared.save(token: "old-refresh", for: "geogarage_refresh_token")
    let log = RequestLog()
    let tokenJSON = self.tokenJSON
    // The /o/token/ response only arrives after the logout: the handler sleeps on the
    // `MockURLProtocol` thread (never on the MainActor), so the request is really in flight.
    MockURLProtocol.setHandler { request in
      log.append(request)
      if request.url?.path == "/o/token" {
        Thread.sleep(forTimeInterval: 1.0)
        return (Self.response(request, status: 200), Data(tokenJSON.utf8))
      }
      return (Self.response(request, status: 404), Data())
    }

    let refresh = Task { try await self.service.refreshTokens() }
    for _ in 0..<200 {
      if log.requests.contains(where: { $0.url?.path == "/o/token" }) { break }
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(log.requests.contains { $0.url?.path == "/o/token" }, "the refresh must have been sent before the logout")

    await service.logout()

    do {
      _ = try await refresh.value
      XCTFail("expected cancelled: the logout cancels the refresh")
    } catch AuthError.cancelled {
      // expected
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    let access = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token")
    let storedRefresh = await KeychainManager.shared.retrieveToken(for: "geogarage_refresh_token")
    XCTAssertNil(access, "a cancelled refresh must not rewrite the tokens after the logout")
    XCTAssertNil(storedRefresh)
    XCTAssertFalse(service.isGeoGarageAuthenticated)
  }

  func testLogoutRemovesPackageSecret() async {
    await KeychainManager.shared.save(token: "access", for: "geogarage_access_token")
    await KeychainManager.shared.save(token: "s3cret", for: GeoGaragePartnerSecretService.keychainAccount)

    await service.logout()

    let secret = await KeychainManager.shared.retrieveToken(for: GeoGaragePartnerSecretService.keychainAccount)
    XCTAssertNil(secret, "the decryption secret goes away with the session")
    let access = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token")
    XCTAssertNil(access)
  }
}
