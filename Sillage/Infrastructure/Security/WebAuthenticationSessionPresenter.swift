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
import OSLog

/// Presents the GeoGarage page through `WebAuthenticationSession` (the `ASWebAuthenticationSession`
/// exposed to SwiftUI by the `\.webAuthenticationSession` environment): system browser, never a
/// WebView (RFC 8252 §8.12), so the password never goes through the app.
struct WebAuthenticationSessionPresenter: GeoGarageAuthorizationPresenting {
  let session: WebAuthenticationSession

  func authorize(url: URL, callbackHost: String, callbackPath: String) async throws -> URL {
    Logger.network.debug("WebAuthenticationSessionPresenter: authenticating (\(url.oauthStructureSummary, privacy: .public), expected callback host: \(callbackHost, privacy: .public), path: \(callbackPath, privacy: .public))")
    do {
      // `.ephemeral`: cookies are not shared with Safari, ensuring that after a logout or when
      // switching accounts, the GeoGarage login screen is presented cleanly instead of auto-logging
      // into the previously cached Safari session. Also avoids the system permission prompt.
      let callbackURL = try await session.authenticate(
        using: url,
        callback: .https(host: callbackHost, path: callbackPath),
        preferredBrowserSession: .ephemeral,
        additionalHeaderFields: [:]
      )
      Logger.network.debug("WebAuthenticationSessionPresenter: received callback (\(callbackURL.oauthCallbackSummary, privacy: .public))")
      return callbackURL
    } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
      Logger.network.debug("WebAuthenticationSessionPresenter: login canceled by user.")
      throw AuthError.cancelled
    } catch is CancellationError {
      // Sign-in task cancelled by the caller (Cancel button, screen dismissed): same silent outcome
      // as the user closing the page.
      Logger.network.debug("WebAuthenticationSessionPresenter: task canceled by caller.")
      throw AuthError.cancelled
    } catch {
      let nsError = error as NSError
      Logger.network.error("WebAuthenticationSessionPresenter: session failed (domain: \(nsError.domain, privacy: .public), code: \(nsError.code, privacy: .public))")
      throw error
    }
  }
}
