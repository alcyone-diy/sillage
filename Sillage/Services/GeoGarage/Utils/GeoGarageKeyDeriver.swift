//
//  GeoGarageKeyDeriver.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CryptoKit

/// Helper utility for deriving the SQLCipher encryption key from the customer ID and shared secret.
nonisolated enum GeoGarageKeyDeriver {
  /// Derives the passphrase string used for SQLCipher PRAGMA key.
  /// Computed as the SHA256 hex digest of "\(sharedSecret):\(customerID)".
  /// - Parameters:
  ///   - sharedSecret: Partner shared secret issued by GeoGarage.
  ///   - customerID: User's GeoGarage customer identifier (`customer_id`).
  /// - Returns: Lowercase 64-character SHA256 hex string.
  static func derivePassphrase(sharedSecret: String, customerID: String) -> String {
    let raw = "\(sharedSecret):\(customerID)"
    let hash = SHA256.hash(data: Data(raw.utf8))
    return hash.map { String(format: "%02x", $0) }.joined()
  }
}
