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

  override func tearDown() {
    try? manager.deleteTokenSync(for: testAccount)
    super.tearDown()
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
    try manager.deleteTokenSync(for: testAccount)
  }

  func testRetrieveValidTokenTrimsWhitespaceAndRejectsEmpty() async throws {
    try await manager.save(token: "  \n\t ", for: testAccount)
    let blankResult = try await manager.retrieveValidToken(for: testAccount)
    XCTAssertNil(blankResult)
    XCTAssertNil(try manager.retrieveValidTokenSync(for: testAccount))

    try await manager.save(token: "  tok_123 \n", for: testAccount)
    let validResult = try await manager.retrieveValidToken(for: testAccount)
    XCTAssertEqual(validResult, "tok_123")
    XCTAssertEqual(try manager.retrieveValidTokenSync(for: testAccount), "tok_123")
  }

  func testServiceAttributeIsolatesFromItemsWithDifferentOrMissingService() throws {
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
    XCTAssertNil(try manager.retrieveTokenSync(for: testAccount))

    // Saving & deleting via KeychainManager must not clobber either item
    try manager.saveSync(token: "sillage-secret", for: testAccount)
    XCTAssertEqual(try manager.retrieveTokenSync(for: testAccount), "sillage-secret")
    try manager.deleteTokenSync(for: testAccount)

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
          try manager.saveSync(token: "token-\(index)", for: account)
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
}
