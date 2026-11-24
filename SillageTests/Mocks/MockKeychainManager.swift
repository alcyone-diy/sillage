//
//  MockKeychainManager.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-10-18.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import os
@testable import Sillage

final class MockKeychainManager: KeychainManaging, @unchecked Sendable {
  private let storage = OSAllocatedUnfairLock<[String: String]>(initialState: [:])
  private let errorLock = OSAllocatedUnfairLock<KeychainError?>(initialState: nil)
  private let migratedAccountsLock = OSAllocatedUnfairLock<[[String]]>(initialState: [])

  var migrationCalls: [[String]] {
    migratedAccountsLock.withLock { $0 }
  }

  init(initialTokens: [String: String] = [:]) {
    storage.withLock { $0 = initialTokens }
  }

  func setStubbedError(_ error: KeychainError?) {
    errorLock.withLock { $0 = error }
  }

  func save(token: String, for account: String) async throws(KeychainError) {
    if let error = errorLock.withLock({ $0 }) {
      throw error
    }
    storage.withLock { $0[account] = token }
  }

  func retrieveToken(for account: String) async throws(KeychainError) -> String? {
    if let error = errorLock.withLock({ $0 }) {
      throw error
    }
    return storage.withLock { $0[account] }
  }

  func deleteToken(for account: String) async throws(KeychainError) {
    if let error = errorLock.withLock({ $0 }) {
      throw error
    }
    storage.withLock { _ = $0.removeValue(forKey: account) }
  }

  func migrateAccessibilityIfNeeded(for accounts: [String]) async throws(KeychainError) {
    if let error = errorLock.withLock({ $0 }) {
      throw error
    }
    migratedAccountsLock.withLock { $0.append(accounts) }
  }

  func clearAll() {
    storage.withLock { $0.removeAll() }
    migratedAccountsLock.withLock { $0.removeAll() }
  }
}
