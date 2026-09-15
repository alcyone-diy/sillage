//
//  MockGeoGarageAuthorizationPresenter.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
@testable import Sillage

/// Mocks the authorization page: returns a callback URL built from the `state` of the received
/// URL (as the portal would), or throws the requested error.
@MainActor
final class MockGeoGarageAuthorizationPresenter: GeoGarageAuthorizationPresenting {
  enum Behaviour {
    case returnCode(String)
    case returnQuery(String)      // e.g. "error=access_denied" (the state is appended)
    case returnRawCallback(URL)   // returned as is (wrong state, etc.)
    case throwError(Error)
  }

  var behaviour: Behaviour = .returnCode("code-123")
  private(set) var lastAuthorizeURL: URL?
  private(set) var lastCallbackScheme: String?
  private(set) var callCount = 0

  func authorize(url: URL, callbackScheme: String) async throws -> URL {
    callCount += 1
    lastAuthorizeURL = url
    lastCallbackScheme = callbackScheme
    let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first { $0.name == "state" }?.value ?? ""
    switch behaviour {
    case .returnCode(let code):
      return try callback("code=\(code)&state=\(state)", scheme: callbackScheme)
    case .returnQuery(let query):
      return try callback("\(query)&state=\(state)", scheme: callbackScheme)
    case .returnRawCallback(let url):
      return url
    case .throwError(let error):
      throw error
    }
  }

  private func callback(_ query: String, scheme: String) throws -> URL {
    guard let url = URL(string: "\(scheme)://oauth2/callback?\(query)") else {
      throw AuthError.invalidResponse
    }
    return url
  }
}
