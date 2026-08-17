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

  func testDerivePassphrase_producesExpectedConcatenation() {
    let secret = "dummy_secret_xyz"
    let customerID = "cus_999"
    let derived = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: secret, customerID: customerID)

    XCTAssertEqual(derived, "cus_999dummy_secret_xyz")
  }

  func testDerivePassphrase_isDeterministic() {
    let derived1 = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: "secretA", customerID: "user1")
    let derived2 = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: "secretA", customerID: "user1")
    let derivedDifferent = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: "secretB", customerID: "user1")

    XCTAssertEqual(derived1, derived2)
    XCTAssertNotEqual(derived1, derivedDifferent)
  }
}
