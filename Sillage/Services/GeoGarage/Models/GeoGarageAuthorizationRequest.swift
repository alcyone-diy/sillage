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

/// Erreurs du retour d'autorisation (`redirect_uri?code=…&state=…`), RFC 6749 §4.1.2 et §4.1.2.1.
nonisolated enum AuthorizationCallbackError: Error, Equatable {
  /// L'utilisateur a refusé sur la page de consentement (`error=access_denied`).
  case accessDenied
  /// `state` absent ou différent de celui envoyé : réponse forgée ou croisée, on la jette.
  case stateMismatch
  /// Ni `code` ni `error` : URL de retour inattendue.
  case missingCode
  /// Autre `error=` du serveur (`invalid_request`, `unauthorized_client`, `server_error`…).
  case serverError(String)
}

/// Requête d'autorisation OAuth2 (authorization code + PKCE) vers accounts.geogarage.com et
/// lecture de son retour. Contrat : docs/partner-oauth2-authorization-code.md du portail
/// (endpoint `/o/authorize/`, méthode S256, code valable 60 s, une seule fois).
nonisolated struct GeoGarageAuthorizationRequest {
  let authorizeEndpoint: URL
  let clientID: String
  let redirectURI: String
  let scope: String
  let state: String
  let codeChallenge: String

  /// URL à ouvrir dans le navigateur système. `nil` seulement si l'endpoint est malformé.
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

  /// Extrait le `code` de l'URL de retour après vérification du `state`.
  static func authorizationCode(
    from callbackURL: URL,
    expectedState: String
  ) throws(AuthorizationCallbackError) -> String {
    let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ name: String) -> String? {
      items.first { $0.name == name }?.value
    }
    // Le state se vérifie avant tout, y compris sur une erreur : un `error=access_denied` forgé
    // sans le bon state ne doit pas être pris pour une réponse du portail.
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
