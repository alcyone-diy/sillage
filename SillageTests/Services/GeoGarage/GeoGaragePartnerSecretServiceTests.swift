//
//  GeoGaragePartnerSecretServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class GeoGaragePartnerSecretServiceTests: XCTestCase {
  private var session: URLSession!

  override func setUp() async throws {
    try await super.setUp()
    MockURLProtocol.reset()
    session = MockURLProtocol.makeMockSession()
    await KeychainManager.shared.deleteToken(for: GeoGaragePartnerSecretService.keychainAccount)
  }

  override func tearDown() async throws {
    await KeychainManager.shared.deleteToken(for: GeoGaragePartnerSecretService.keychainAccount)
    MockURLProtocol.reset()
    session = nil
    try await super.tearDown()
  }

  private static func response(_ request: URLRequest, status: Int) -> HTTPURLResponse {
    let url = request.url ?? URL(fileURLWithPath: "/")
    return HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) ?? HTTPURLResponse()
  }

  func testRefreshSendsBearerStoresSecretAndReturnsCustomerID() async throws {
    MockURLProtocol.setHandler { request in
      XCTAssertEqual(request.httpMethod, "GET")
      XCTAssertEqual(request.url?.path, "/partners/me")  // URL.path retire le "/" final
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
      XCTAssertNil(request.url?.query, "jamais de token en query string")
      let json = #"{"client_id":"abc","customer_id":"cus_1","package_secret":"s3cret","tea_secret":""}"#
      return (Self.response(request, status: 200), Data(json.utf8))
    }
    let service = GeoGaragePartnerSecretService(session: session)

    let secrets = try await service.refresh(accessToken: "tok")

    XCTAssertEqual(secrets.clientID, "abc")
    XCTAssertEqual(secrets.customerID, "cus_1")
    XCTAssertEqual(secrets.packageSecret, "s3cret")
    XCTAssertEqual(secrets.teaSecret, "")
    let stored = await KeychainManager.shared.retrieveToken(for: GeoGaragePartnerSecretService.keychainAccount)
    XCTAssertEqual(stored, "s3cret")
  }

  func testRefreshDecodesNullCustomerID() async throws {
    MockURLProtocol.setHandler { request in
      let json = #"{"client_id":"abc","customer_id":null,"package_secret":"s3cret","tea_secret":""}"#
      return (Self.response(request, status: 200), Data(json.utf8))
    }
    let service = GeoGaragePartnerSecretService(session: session)

    let secrets = try await service.refresh(accessToken: "tok")

    XCTAssertNil(secrets.customerID, "utilisateur jamais abonné : le portail renvoie null")
  }

  func testRefreshThrowsUnauthorizedOn403AndStoresNothing() async {
    MockURLProtocol.setHandler { request in (Self.response(request, status: 403), Data()) }
    let service = GeoGaragePartnerSecretService(session: session)

    do {
      _ = try await service.refresh(accessToken: "tok")
      XCTFail("unauthorized attendu")
    } catch PartnerSecretError.unauthorized {
      // attendu
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
    let stored = await KeychainManager.shared.retrieveToken(for: GeoGaragePartnerSecretService.keychainAccount)
    XCTAssertNil(stored)
  }

  func testRefreshThrowsNoProfileOn404() async {
    MockURLProtocol.setHandler { request in (Self.response(request, status: 404), Data(#"{"error":"unknown"}"#.utf8)) }
    let service = GeoGaragePartnerSecretService(session: session)

    do {
      _ = try await service.refresh(accessToken: "tok")
      XCTFail("noProfile attendu")
    } catch PartnerSecretError.noProfile {
      // attendu : Application sans fiche, fiche désactivée, ou Application en grant password
    } catch {
      XCTFail("erreur inattendue : \(error)")
    }
  }
}
