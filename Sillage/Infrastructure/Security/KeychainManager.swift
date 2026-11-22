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

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: account
    ]

    let attributesToUpdate: [String: Any] = [
      kSecValueData as String: data
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
    if updateStatus == errSecSuccess {
      return
    }

    if updateStatus != errSecItemNotFound {
      Logger.system.error("Keychain update failed for account '\(account, privacy: .public)' with OSStatus \(updateStatus, privacy: .public).")
      throw KeychainError.unexpectedStatus(updateStatus)
    }

    let newItem: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]

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
}
