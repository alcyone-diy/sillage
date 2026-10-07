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

/// Opens the GeoGarage authorization page in the system browser and returns the callback URL
/// (`https://callbackHost/callbackPath?code=…&state=…`). Abstracts ASWebAuthenticationSession so the Services
/// layer and the tests do not depend on AuthenticationServices.
/// A user cancellation must be thrown as `AuthError.cancelled`.
protocol GeoGarageAuthorizationPresenting {
  func authorize(url: URL, callbackHost: String, callbackPath: String) async throws -> URL
}
