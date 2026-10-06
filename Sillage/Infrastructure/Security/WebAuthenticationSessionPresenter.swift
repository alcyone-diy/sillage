//
//  WebAuthenticationSessionPresenter.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import AuthenticationServices

/// Presents the GeoGarage page through `WebAuthenticationSession` (the `ASWebAuthenticationSession`
/// exposed to SwiftUI by the `\.webAuthenticationSession` environment): system browser, never a
/// WebView (RFC 8252 §8.12), so the password never goes through the app.
struct WebAuthenticationSessionPresenter: GeoGarageAuthorizationPresenting {
  let session: WebAuthenticationSession

  func authorize(url: URL, callbackScheme: String) async throws -> URL {
    do {
      // `.shared`: cookies are shared with Safari, so an existing GeoGarage session is reused and the
      // portal's automatic consent asks nothing on later sign-ins. iOS shows its one-time
      // "wants to use accounts.geogarage.com to sign in" prompt: expected.
      return try await session.authenticate(
        using: url,
        callback: .customScheme(callbackScheme),
        preferredBrowserSession: .shared,
        additionalHeaderFields: [:]
      )
    } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
      throw AuthError.cancelled
    } catch is CancellationError {
      // Sign-in task cancelled by the caller (Cancel button, screen dismissed): same silent outcome
      // as the user closing the page.
      throw AuthError.cancelled
    }
  }
}
