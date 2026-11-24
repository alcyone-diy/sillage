//
//  KeychainManager.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog
import Security

public enum KeychainError: LocalizedError, Equatable, Sendable {
  case unexpectedStatus(OSStatus)
  case encodingFailed
  case decodingFailed

  /// Indicates whether the Keychain rejected access because device data protection is currently locked
  /// (e.g. Before First Unlock after reboot, or legacy `WhenUnlocked` item read while screen is locked).
  public var isInteractionNotAllowed: Bool {
    if case .unexpectedStatus(let status) = self {
      return status == errSecInteractionNotAllowed
    }
    return false
  }

  public var errorDescription: String? {
    switch self {
    case .unexpectedStatus(let status):
      if let message = SecCopyErrorMessageString(status, nil) as String? {
        return "Keychain error (\(status)): \(message)"
      }
      return "Keychain error with OSStatus: \(status)"
    case .encodingFailed:
      return "Failed to encode token as UTF-8 data."
    case .decodingFailed:
      return "Failed to decode Keychain item data as UTF-8 string."
    }
  }
}

public protocol KeychainManaging: Sendable {
  func save(token: String, for account: String) async throws(KeychainError)
  func retrieveToken(for account: String) async throws(KeychainError) -> String?
  func deleteToken(for account: String) async throws(KeychainError)
  func migrateAccessibilityIfNeeded(for accounts: [String]) async throws(KeychainError)
}

extension KeychainManaging {
  public func retrieveValidToken(for account: String) async throws(KeychainError) -> String? {
    guard let token = try await retrieveToken(for: account)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !token.isEmpty else {
      return nil
    }
    return token
  }
}

/// A lightweight, robust manager for securely storing and retrieving items in the iOS Keychain.
/// Implemented as an `actor` so async callers always leave `@MainActor` and serialize `SecItem*` access.
actor KeychainManager: KeychainManaging {
  static let shared = KeychainManager()

  private static let service = "com.alcyone-sillage.sillage"

  private init() {}

  /// Saves a token to the Keychain asynchronously.
  func save(token: String, for account: String) throws(KeychainError) {
    guard let data = token.data(using: .utf8) else {
      Logger.system.error("Keychain save failed for account '\(account, privacy: .public)': UTF-8 encoding failed.")
      throw KeychainError.encodingFailed
    }

    // IMPORTANT: Never include `kSecAttrAccessible` in `query` dictionaries for `SecItemCopyMatching`,
    // `SecItemUpdate`, or `SecItemDelete` so existing items created under an older accessibility class remain visible.
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: account
    ]

    let attributesToUpdate: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]

    let newItem: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
    if updateStatus == errSecSuccess {
      return
    }

    if updateStatus == errSecParam {
      let deleteStatus = SecItemDelete(query as CFDictionary)
      guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
        Logger.system.error("Keychain fallback delete failed for account '\(account, privacy: .public)' with OSStatus \(deleteStatus, privacy: .public).")
        throw KeychainError.unexpectedStatus(deleteStatus)
      }
      let replaceStatus = SecItemAdd(newItem as CFDictionary, nil)
      if replaceStatus == errSecSuccess {
        return
      }
      Logger.system.error("Keychain fallback add failed for account '\(account, privacy: .public)' with OSStatus \(replaceStatus, privacy: .public).")
      throw KeychainError.unexpectedStatus(replaceStatus)
    }

    if updateStatus != errSecItemNotFound {
      Logger.system.error("Keychain update failed for account '\(account, privacy: .public)' with OSStatus \(updateStatus, privacy: .public).")
      throw KeychainError.unexpectedStatus(updateStatus)
    }

    let addStatus = SecItemAdd(newItem as CFDictionary, nil)
    if addStatus == errSecSuccess {
      return
    }

    // Handle race condition where another thread inserted the item between SecItemUpdate and SecItemAdd.
    if addStatus == errSecDuplicateItem {
      let retryStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
      if retryStatus == errSecSuccess {
        return
      }
      Logger.system.error("Keychain retry update failed for account '\(account, privacy: .public)' with OSStatus \(retryStatus, privacy: .public).")
      throw KeychainError.unexpectedStatus(retryStatus)
    }

    Logger.system.error("Keychain add failed for account '\(account, privacy: .public)' with OSStatus \(addStatus, privacy: .public).")
    throw KeychainError.unexpectedStatus(addStatus)
  }

  /// Retrieves a token from the Keychain asynchronously.
  func retrieveToken(for account: String) throws(KeychainError) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: kCFBooleanTrue as Any,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    if status == errSecItemNotFound {
      return nil
    }

    guard status == errSecSuccess else {
      Logger.system.error("Keychain retrieve failed for account '\(account, privacy: .public)' with OSStatus \(status, privacy: .public).")
      throw KeychainError.unexpectedStatus(status)
    }

    guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
      Logger.system.error("Keychain retrieve failed for account '\(account, privacy: .public)': UTF-8 decoding failed.")
      throw KeychainError.decodingFailed
    }

    return token
  }

  /// Deletes a token from the Keychain asynchronously.
  func deleteToken(for account: String) throws(KeychainError) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: account
    ]

    let status = SecItemDelete(query as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound {
      return
    }

    Logger.system.error("Keychain delete failed for account '\(account, privacy: .public)' with OSStatus \(status, privacy: .public).")
    throw KeychainError.unexpectedStatus(status)
  }

  /// Idempotently migrates existing Keychain items to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
  /// so background chart downloads and tile decryption succeed while the device screen is locked.
  func migrateAccessibilityIfNeeded(for accounts: [String]) throws(KeychainError) {
    let targetAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    for account in accounts {
      let readQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: account,
        kSecReturnAttributes as String: kCFBooleanTrue as Any,
        kSecReturnData as String: kCFBooleanTrue as Any,
        kSecMatchLimit as String: kSecMatchLimitOne
      ]

      var result: CFTypeRef?
      let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &result)
      if readStatus == errSecItemNotFound {
        continue
      }

      guard readStatus == errSecSuccess else {
        Logger.system.warning("Keychain accessibility check failed for account '\(account, privacy: .public)' with OSStatus \(readStatus, privacy: .public).")
        throw KeychainError.unexpectedStatus(readStatus)
      }

      guard let attributes = result as? [String: Any] else {
        continue
      }

      let currentAccessible = attributes[kSecAttrAccessible as String] as? String
      if currentAccessible == targetAccessible {
        continue
      }

      let matchQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: account
      ]
      let attributesToUpdate: [String: Any] = [
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      ]

      let updateStatus = SecItemUpdate(matchQuery as CFDictionary, attributesToUpdate as CFDictionary)
      if updateStatus == errSecSuccess {
        Logger.system.info("Migrated Keychain accessibility to AfterFirstUnlockThisDeviceOnly for account '\(account, privacy: .public)'.")
        continue
      }

      if updateStatus == errSecParam, let existingData = attributes[kSecValueData as String] as? Data {
        let deleteStatus = SecItemDelete(matchQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
          Logger.system.error("Keychain migration fallback delete failed for account '\(account, privacy: .public)' with OSStatus \(deleteStatus, privacy: .public).")
          throw KeychainError.unexpectedStatus(deleteStatus)
        }
        let replacementItem: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: Self.service,
          kSecAttrAccount as String: account,
          kSecValueData as String: existingData,
          kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let addStatus = SecItemAdd(replacementItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
          Logger.system.error("Keychain migration fallback add failed for account '\(account, privacy: .public)' with OSStatus \(addStatus, privacy: .public).")
          throw KeychainError.unexpectedStatus(addStatus)
        }
        Logger.system.info("Migrated Keychain accessibility via replace to AfterFirstUnlockThisDeviceOnly for account '\(account, privacy: .public)'.")
        continue
      }

      Logger.system.error("Keychain accessibility migration failed for account '\(account, privacy: .public)' with OSStatus \(updateStatus, privacy: .public).")
      throw KeychainError.unexpectedStatus(updateStatus)
    }
  }
}
