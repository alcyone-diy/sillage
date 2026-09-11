//
//  GeoGarageAuthorizationPresenting.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Ouvre la page d'autorisation GeoGarage dans le navigateur système et rend l'URL de retour
/// (`callbackScheme://…?code=…&state=…`). Abstraction d'ASWebAuthenticationSession pour que la
/// couche Services et les tests ne dépendent pas d'AuthenticationServices (11 sept. 2026).
/// Une annulation par l'utilisateur doit être levée comme `AuthError.cancelled`.
protocol GeoGarageAuthorizationPresenting {
  func authorize(url: URL, callbackScheme: String) async throws -> URL
}
