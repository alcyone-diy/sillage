//
//  GeoGarageAuthorizationRequestTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

final class GeoGarageAuthorizationRequestTests: XCTestCase {

  private func makeRequest() throws -> GeoGarageAuthorizationRequest {
    let endpoint = try XCTUnwrap(URL(string: "https://accounts.geogarage.com/o/authorize/"))
    return GeoGarageAuthorizationRequest(
      authorizeEndpoint: endpoint,
      clientID: "client-abc",
      redirectURI: AppConstants.GeoGarage.oauthRedirectURI,
      scope: AppConstants.GeoGarage.oauthScope,
      state: "state-xyz",
      codeChallenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    )
  }

  private func queryItems(of url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
  }

  func testURLCarriesEveryPKCEParameter() throws {
    let url = try XCTUnwrap(makeRequest().url)
    XCTAssertEqual(url.host, "accounts.geogarage.com")
    // `URL.path` drops the trailing "/"; `absoluteString` below checks the original "/" is kept.
    XCTAssertEqual(url.path, "/o/authorize")
    XCTAssertTrue(url.absoluteString.hasPrefix("https://accounts.geogarage.com/o/authorize/?"), url.absoluteString)
    let query = queryItems(of: url)
    XCTAssertEqual(query["response_type"], "code")
    XCTAssertEqual(query["client_id"], "client-abc")
    XCTAssertEqual(query["redirect_uri"], "com.alcyone-sillage.app://oauth2/callback")
    XCTAssertEqual(query["scope"], "write read")
    XCTAssertEqual(query["state"], "state-xyz")
    XCTAssertEqual(query["code_challenge"], "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    XCTAssertEqual(query["code_challenge_method"], "S256")
    XCTAssertEqual(query.count, 7)
  }

  func testAuthorizationCodeIsExtractedWhenStateMatches() throws {
    let callback = try XCTUnwrap(URL(string: "com.alcyone-sillage.app://oauth2/callback?code=abc123&state=state-xyz"))
    XCTAssertEqual(try GeoGarageAuthorizationRequest.authorizationCode(from: callback, expectedState: "state-xyz"), "abc123")
  }

  func testStateMismatchIsRejectedEvenWithACode() throws {
    let callback = try XCTUnwrap(URL(string: "com.alcyone-sillage.app://oauth2/callback?code=abc123&state=other"))
    XCTAssertThrowsError(try GeoGarageAuthorizationRequest.authorizationCode(from: callback, expectedState: "state-xyz")) { error in
      XCTAssertEqual(error as? AuthorizationCallbackError, .stateMismatch)
    }
  }

  func testMissingStateIsRejected() throws {
    let callback = try XCTUnwrap(URL(string: "com.alcyone-sillage.app://oauth2/callback?code=abc123"))
    XCTAssertThrowsError(try GeoGarageAuthorizationRequest.authorizationCode(from: callback, expectedState: "state-xyz")) { error in
      XCTAssertEqual(error as? AuthorizationCallbackError, .stateMismatch)
    }
  }

  func testAccessDeniedIsReported() throws {
    let callback = try XCTUnwrap(URL(string: "com.alcyone-sillage.app://oauth2/callback?error=access_denied&state=state-xyz"))
    XCTAssertThrowsError(try GeoGarageAuthorizationRequest.authorizationCode(from: callback, expectedState: "state-xyz")) { error in
      XCTAssertEqual(error as? AuthorizationCallbackError, .accessDenied)
    }
  }

  func testOtherServerErrorIsReportedWithItsCode() throws {
    let callback = try XCTUnwrap(URL(string: "com.alcyone-sillage.app://oauth2/callback?error=unauthorized_client&state=state-xyz"))
    XCTAssertThrowsError(try GeoGarageAuthorizationRequest.authorizationCode(from: callback, expectedState: "state-xyz")) { error in
      XCTAssertEqual(error as? AuthorizationCallbackError, .serverError("unauthorized_client"))
    }
  }

  func testCallbackWithoutCodeNorErrorIsRejected() throws {
    let callback = try XCTUnwrap(URL(string: "com.alcyone-sillage.app://oauth2/callback?state=state-xyz"))
    XCTAssertThrowsError(try GeoGarageAuthorizationRequest.authorizationCode(from: callback, expectedState: "state-xyz")) { error in
      XCTAssertEqual(error as? AuthorizationCallbackError, .missingCode)
    }
  }
}
