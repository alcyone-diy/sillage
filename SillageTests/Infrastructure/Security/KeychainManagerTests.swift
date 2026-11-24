//
//  KeychainManagerTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Security
import XCTest
@testable import Sillage

final class KeychainManagerTests: XCTestCase {
  private let manager = KeychainManager.shared
  private let testAccount = "com.alcyone-sillage.tests.\(UUID().uuidString)"

  override func tearDown() async throws {
    try? await manager.deleteToken(for: testAccount)
    try await super.tearDown()
  }

  func testSaveRetrieveAndDeleteAsync() async throws {
    let initial = try await manager.retrieveToken(for: testAccount)
    XCTAssertNil(initial)

    try await manager.save(token: "secret-1", for: testAccount)
    let retrieved = try await manager.retrieveToken(for: testAccount)
    XCTAssertEqual(retrieved, "secret-1")

    // Upsert overwrites the existing value
    try await manager.save(token: "secret-2", for: testAccount)
    let updated = try await manager.retrieveToken(for: testAccount)
    XCTAssertEqual(updated, "secret-2")

    try await manager.deleteToken(for: testAccount)
    let afterDelete = try await manager.retrieveToken(for: testAccount)
    XCTAssertNil(afterDelete)
  }

  func testDeleteIsIdempotentWhenItemDoesNotExist() async throws {
    try await manager.deleteToken(for: testAccount)
    try await manager.deleteToken(for: testAccount)
  }

  func testRetrieveValidTokenTrimsWhitespaceAndRejectsEmpty() async throws {
    try await manager.save(token: "  \n\t ", for: testAccount)
    let blankResult = try await manager.retrieveValidToken(for: testAccount)
    XCTAssertNil(blankResult)

    try await manager.save(token: "  tok_123 \n", for: testAccount)
    let validResult = try await manager.retrieveValidToken(for: testAccount)
    XCTAssertEqual(validResult, "tok_123")
  }

  func testServiceAttributeIsolatesFromItemsWithDifferentOrMissingService() async throws {
    let foreignQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.example.other-service",
      kSecAttrAccount as String: testAccount as String,
      kSecValueData as String: Data("foreign-secret".utf8)
    ]
    let missingServiceQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: testAccount as String,
      kSecValueData as String: Data("legacy-no-service-secret".utf8)
    ]

    SecItemDelete(foreignQuery as CFDictionary)
    SecItemDelete(missingServiceQuery as CFDictionary)
    XCTAssertEqual(SecItemAdd(foreignQuery as CFDictionary, nil), errSecSuccess)
    XCTAssertEqual(SecItemAdd(missingServiceQuery as CFDictionary, nil), errSecSuccess)

    addTeardownBlock {
      SecItemDelete(foreignQuery as CFDictionary)
      SecItemDelete(missingServiceQuery as CFDictionary)
    }

    // KeychainManager uses kSecAttrService = "com.alcyone-sillage.sillage", so it must not see either item
    let initial = try await manager.retrieveToken(for: testAccount)
    XCTAssertNil(initial)

    // Saving & deleting via KeychainManager must not clobber either item
    try await manager.save(token: "sillage-secret", for: testAccount)
    let saved = try await manager.retrieveToken(for: testAccount)
    XCTAssertEqual(saved, "sillage-secret")
    try await manager.deleteToken(for: testAccount)

    var foreignItem: CFTypeRef?
    let foreignReadQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.example.other-service",
      kSecAttrAccount as String: testAccount as String,
      kSecReturnData as String: kCFBooleanTrue as Any,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    XCTAssertEqual(SecItemCopyMatching(foreignReadQuery as CFDictionary, &foreignItem), errSecSuccess)
    XCTAssertEqual((foreignItem as? Data).flatMap { String(data: $0, encoding: .utf8) }, "foreign-secret")

    var missingServiceItem: CFTypeRef?
    let missingServiceReadQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "",
      kSecAttrAccount as String: testAccount as String,
      kSecReturnData as String: kCFBooleanTrue as Any,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    XCTAssertEqual(SecItemCopyMatching(missingServiceReadQuery as CFDictionary, &missingServiceItem), errSecSuccess)
    XCTAssertEqual((missingServiceItem as? Data).flatMap { String(data: $0, encoding: .utf8) }, "legacy-no-service-secret")
  }

  func testConcurrentSavesDoNotFailWithDuplicateItem() async throws {
    let account = testAccount
    let manager = self.manager
    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<20 {
        group.addTask {
          try await manager.save(token: "token-\(index)", for: account)
        }
      }
      try await group.waitForAll()
    }

    let finalValue = try await manager.retrieveToken(for: account)
    XCTAssertNotNil(finalValue)
    XCTAssertTrue(finalValue?.hasPrefix("token-") == true)
  }

  func testKeychainErrorDescriptions() {
    XCTAssertNotNil(KeychainError.encodingFailed.errorDescription)
    XCTAssertNotNil(KeychainError.decodingFailed.errorDescription)
    XCTAssertNotNil(KeychainError.unexpectedStatus(errSecInteractionNotAllowed).errorDescription)
  }

  func testIsInteractionNotAllowedAndAllAccounts() {
    XCTAssertTrue(KeychainError.unexpectedStatus(errSecInteractionNotAllowed).isInteractionNotAllowed)
    XCTAssertFalse(KeychainError.unexpectedStatus(errSecItemNotFound).isInteractionNotAllowed)
    XCTAssertFalse(KeychainError.encodingFailed.isInteractionNotAllowed)

    XCTAssertEqual(
      Set(GeoGarageKeychainKeys.allAccounts),
      Set([
        GeoGarageKeychainKeys.accessToken,
        GeoGarageKeychainKeys.refreshToken,
        GeoGarageKeychainKeys.packageSecret,
        GeoGarageKeychainKeys.customerID
      ])
    )
  }

  func testSave_setsAfterFirstUnlockThisDeviceOnlyAccessibility() async throws {
    try await manager.save(token: "token-after-first-unlock", for: testAccount)

    let accessible = readAccessibleAttribute(for: testAccount)
    XCTAssertEqual(accessible, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
  }

  func testLegacyWhenUnlockedItem_retrieveMigrateIdempotentlyUpsertAndDelete() async throws {
    try insertLegacyWhenUnlockedItem(token: "legacy-token-value", for: testAccount)
    XCTAssertEqual(readAccessibleAttribute(for: testAccount), kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)

    // 1. `retrieveToken` must not filter by `kSecAttrAccessible` in `query`
    let initialRead = try await manager.retrieveToken(for: testAccount)
    XCTAssertEqual(initialRead, "legacy-token-value")

    // 2. `migrateAccessibilityIfNeeded` upgrades to `AfterFirstUnlockThisDeviceOnly` and ignores missing accounts
    let missingAccount = "com.alcyone-sillage.tests.missing.\(UUID().uuidString)"
    try await manager.migrateAccessibilityIfNeeded(for: [missingAccount, testAccount])
    XCTAssertEqual(readAccessibleAttribute(for: testAccount), kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    let afterMigration = try await manager.retrieveToken(for: testAccount)
    XCTAssertEqual(afterMigration, "legacy-token-value")

    // 3. Second migration call is idempotent
    try await manager.migrateAccessibilityIfNeeded(for: [testAccount])
    XCTAssertEqual(readAccessibleAttribute(for: testAccount), kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    let afterIdempotentCall = try await manager.retrieveToken(for: testAccount)
    XCTAssertEqual(afterIdempotentCall, "legacy-token-value")

    // 4. `deleteToken` and `save` upsert also handle legacy `WhenUnlocked` items cleanly
    try await manager.deleteToken(for: testAccount)
    try insertLegacyWhenUnlockedItem(token: "legacy-v1", for: testAccount)
    XCTAssertEqual(readAccessibleAttribute(for: testAccount), kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)

    try await manager.save(token: "upgraded-v2", for: testAccount)
    XCTAssertEqual(readAccessibleAttribute(for: testAccount), kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    let afterUpsert = try await manager.retrieveToken(for: testAccount)
    XCTAssertEqual(afterUpsert, "upgraded-v2")

    // 5. Deleting a legacy `WhenUnlocked` item directly succeeds
    try await manager.deleteToken(for: testAccount)
    try insertLegacyWhenUnlockedItem(token: "legacy-to-delete", for: testAccount)
    try await manager.deleteToken(for: testAccount)
    let afterFinalDelete = try await manager.retrieveToken(for: testAccount)
    XCTAssertNil(afterFinalDelete)
  }

  // MARK: - Raw Security.framework Helpers

  private func insertLegacyWhenUnlockedItem(token: String, for account: String) throws {
    let legacyItem: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.alcyone-sillage.sillage",
      kSecAttrAccount as String: account,
      kSecValueData as String: Data(token.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    XCTAssertEqual(SecItemAdd(legacyItem as CFDictionary, nil), errSecSuccess)
  }

  private func readAccessibleAttribute(for account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.alcyone-sillage.sillage",
      kSecAttrAccount as String: account,
      kSecReturnAttributes as String: kCFBooleanTrue as Any,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let attributes = item as? [String: Any] else {
      return nil
    }
    return attributes[kSecAttrAccessible as String] as? String
  }
}
