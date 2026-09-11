//
//  GeoGaragePKCE.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CryptoKit

/// PKCE (RFC 7636) pour la connexion GeoGarage en authorization code (11 sept. 2026) : l'app est
/// un client public sans secret, le couple code_verifier / code_challenge remplace le client_secret
/// et protège l'interception du code de retour sur le schéma privé (RFC 8252 §8.1).
nonisolated enum GeoGaragePKCE {

  /// 32 octets aléatoires en base64url = 43 caractères de l'alphabet non réservé (RFC 7636 §4.1).
  static func makeCodeVerifier() -> String {
    base64URL(randomBytes(count: 32))
  }

  /// `code_challenge` = base64url(SHA-256(code_verifier)) sans `=` : méthode S256 (RFC 7636 §4.2).
  static func codeChallenge(for verifier: String) -> String {
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return base64URL(Data(digest))
  }

  /// `state` anti-CSRF : 16 octets aléatoires en base64url (22 caractères).
  static func makeState() -> String {
    base64URL(randomBytes(count: 16))
  }

  private static func randomBytes(count: Int) -> Data {
    // SystemRandomNumberGenerator est cryptographiquement sûr sur les plateformes Apple.
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
