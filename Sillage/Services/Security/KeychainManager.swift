//
//  KeychainManager.swift
//  Alcyone Sillage
//
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Security

/// A lightweight, robust manager for securely storing and retrieving items in the iOS Keychain.
struct KeychainManager {
  static let shared = KeychainManager()

  private init() {}

  /// Saves a token to the Keychain for a specific account. Updates the item if it already exists.
  func save(token: String, for account: String) {
    guard let data = token.data(using: .utf8) else { return }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account
    ]

    let attributesToUpdate: [String: Any] = [
      kSecValueData as String: data
    ]

    // Attempt to update the existing item
    let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

    // If the item doesn't exist, add it
    if status == errSecItemNotFound {
      let newItem: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: account,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      ]
      SecItemAdd(newItem as CFDictionary, nil)
    }
  }

  /// Retrieves a token from the Keychain for a specific account.
  func retrieveToken(for account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
      kSecReturnData as String: kCFBooleanTrue!,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    if status == errSecSuccess, let data = item as? Data {
      return String(data: data, encoding: .utf8)
    }

    return nil
  }

  /// Deletes a token from the Keychain for a specific account.
  func deleteToken(for account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account
    ]

    SecItemDelete(query as CFDictionary)
  }
}
