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

/// PKCE (RFC 7636) for the GeoGarage authorization code sign-in: the app is a public client with
/// no secret, so the code_verifier / code_challenge pair replaces the client_secret and protects
/// against interception of the callback code on the private scheme (RFC 8252 §8.1).
nonisolated enum GeoGaragePKCE {

  /// 32 random bytes in base64url = 43 characters of the unreserved alphabet (RFC 7636 §4.1).
  static func makeCodeVerifier() -> String {
    base64URL(randomBytes(count: 32))
  }

  /// `code_challenge` = base64url(SHA-256(code_verifier)) without `=`: S256 method (RFC 7636 §4.2).
  static func codeChallenge(for verifier: String) -> String {
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return base64URL(Data(digest))
  }

  /// Anti-CSRF `state`: 16 random bytes in base64url (22 characters).
  static func makeState() -> String {
    base64URL(randomBytes(count: 16))
  }

  private static func randomBytes(count: Int) -> Data {
    // SystemRandomNumberGenerator is cryptographically secure on Apple platforms.
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
