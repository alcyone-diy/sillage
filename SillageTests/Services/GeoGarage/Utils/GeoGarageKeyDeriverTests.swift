//
//  GeoGarageKeyDeriverTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CryptoKit
@testable import Sillage

final class GeoGarageKeyDeriverTests: XCTestCase {

  func testDerivePassphrase_producesExpectedSHA256Hex() {
    let secret = "my_secret_key"
    let customerID = "cus_12345"
    let derived = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: secret, customerID: customerID)

    let expectedRaw = "\(secret):\(customerID)"
    let expectedHash = SHA256.hash(data: Data(expectedRaw.utf8)).map { String(format: "%02x", $0) }.joined()

    XCTAssertEqual(derived, expectedHash)
    XCTAssertEqual(derived.count, 64)
  }

  func testDerivePassphrase_isDeterministic() {
    let derived1 = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: "secretA", customerID: "user1")
    let derived2 = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: "secretA", customerID: "user1")
    let derivedDifferent = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: "secretB", customerID: "user1")

    XCTAssertEqual(derived1, derived2)
    XCTAssertNotEqual(derived1, derivedDifferent)
  }
}
