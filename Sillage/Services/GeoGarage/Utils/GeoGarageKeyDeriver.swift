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
  /// Computed as the direct concatenation "\(customerID)\(sharedSecret)".
  /// - Parameters:
  ///   - sharedSecret: Partner shared secret issued by GeoGarage.
  ///   - customerID: User's GeoGarage customer identifier (`customer_id`).
  /// - Returns: Passphrase string passed to SQLCipher.
  static func derivePassphrase(sharedSecret: String, customerID: String) -> String {
    return "\(customerID)\(sharedSecret)"
  }
}
