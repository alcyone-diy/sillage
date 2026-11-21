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

  init(initialTokens: [String: String] = [:]) {
    storage.withLock { $0 = initialTokens }
  }

  func setStubbedError(_ error: KeychainError?) {
    errorLock.withLock { $0 = error }
  }

  func save(token: String, for account: String) async throws(KeychainError) {
    try saveSync(token: token, for: account)
  }

  func retrieveToken(for account: String) async throws(KeychainError) -> String? {
    try retrieveTokenSync(for: account)
  }

  func deleteToken(for account: String) async throws(KeychainError) {
    try deleteTokenSync(for: account)
  }

  func saveSync(token: String, for account: String) throws(KeychainError) {
    if let error = errorLock.withLock({ $0 }) {
      throw error
    }
    storage.withLock { $0[account] = token }
  }

  func retrieveTokenSync(for account: String) throws(KeychainError) -> String? {
    if let error = errorLock.withLock({ $0 }) {
      throw error
    }
    return storage.withLock { $0[account] }
  }

  func deleteTokenSync(for account: String) throws(KeychainError) {
    if let error = errorLock.withLock({ $0 }) {
      throw error
    }
    storage.withLock { _ = $0.removeValue(forKey: account) }
  }

  func clearAll() {
    storage.withLock { $0.removeAll() }
  }
}
