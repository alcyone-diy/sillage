//
//  GeoGarageAuthorizationRequest.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Errors of the authorization callback (`redirect_uri?code=…&state=…`), RFC 6749 §4.1.2 and §4.1.2.1.
nonisolated enum AuthorizationCallbackError: Error, Equatable {
  /// The user declined on the consent page (`error=access_denied`).
  case accessDenied
  /// `state` missing or different from the one sent: forged or crossed response, discarded.
  case stateMismatch
  /// Neither `code` nor `error`: unexpected callback URL.
  case missingCode
  /// Any other server `error=` (`invalid_request`, `unauthorized_client`, `server_error`…).
  case serverError(String)
}

/// OAuth2 authorization request (authorization code + PKCE) to accounts.geogarage.com and parsing
/// of its callback. Endpoint `/o/authorize/`, method S256; the code is valid for 60 s, single-use.
nonisolated struct GeoGarageAuthorizationRequest {
  let authorizeEndpoint: URL
  let clientID: String
  let redirectURI: String
  let scope: String
  let state: String
  let codeChallenge: String

  /// URL to open in the system browser. `nil` only when the endpoint is malformed.
  var url: URL? {
    var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "scope", value: scope),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge", value: codeChallenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    return components?.url
  }

  /// Extracts the `code` from the callback URL after checking the `state`.
  static func authorizationCode(
    from callbackURL: URL,
    expectedState: String
  ) throws(AuthorizationCallbackError) -> String {
    let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ name: String) -> String? {
      items.first { $0.name == name }?.value
    }
    // Check the state first, even on an error: a forged `error=access_denied` without the right
    // state must not be taken for a portal response.
    guard let state = value("state"), state == expectedState else {
      throw AuthorizationCallbackError.stateMismatch
    }
    if let error = value("error") {
      throw error == "access_denied" ? AuthorizationCallbackError.accessDenied : .serverError(error)
    }
    guard let code = value("code"), !code.isEmpty else {
      throw AuthorizationCallbackError.missingCode
    }
    return code
  }
}
