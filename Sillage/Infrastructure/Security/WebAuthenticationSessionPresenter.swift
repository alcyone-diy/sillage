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

/// Présente la page GeoGarage via `WebAuthenticationSession` (l'`ASWebAuthenticationSession`
/// exposée à SwiftUI par l'environnement `\.webAuthenticationSession`) : navigateur système,
/// jamais de WebView (RFC 8252 §8.12), le mot de passe ne transite pas par l'app.
struct WebAuthenticationSessionPresenter: GeoGarageAuthorizationPresenting {
  let session: WebAuthenticationSession

  func authorize(url: URL, callbackScheme: String) async throws -> URL {
    do {
      // `.shared` : cookies partagés avec Safari, la session GeoGarage déjà ouverte est réutilisée et
      // le consentement « auto » du portail ne redemande rien au second passage. iOS affiche une fois
      // « Sillage souhaite utiliser accounts.geogarage.com pour se connecter » : attendu.
      return try await session.authenticate(
        using: url,
        callback: .customScheme(callbackScheme),
        preferredBrowserSession: .shared,
        additionalHeaderFields: [:]
      )
    } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
      throw AuthError.cancelled
    }
  }
}
