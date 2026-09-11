//
//  GeoGaragePKCETests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

final class GeoGaragePKCETests: XCTestCase {

  /// Vecteur de test de la RFC 7636, annexe B.
  func testCodeChallengeMatchesRFC7636Vector() {
    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    XCTAssertEqual(GeoGaragePKCE.codeChallenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
  }

  func testCodeVerifierIs43UnreservedCharactersAndRandom() throws {
    let first = GeoGaragePKCE.makeCodeVerifier()
    let second = GeoGaragePKCE.makeCodeVerifier()
    let unreserved = try Regex("^[A-Za-z0-9._~-]{43}$")
    XCTAssertNotNil(first.wholeMatch(of: unreserved), "verifier: \(first)")
    XCTAssertNotNil(second.wholeMatch(of: unreserved), "verifier: \(second)")
    XCTAssertNotEqual(first, second)
  }

  func testStateIs22URLSafeCharactersAndRandom() throws {
    let first = GeoGaragePKCE.makeState()
    let second = GeoGaragePKCE.makeState()
    let urlSafe = try Regex("^[A-Za-z0-9_-]{22}$")
    XCTAssertNotNil(first.wholeMatch(of: urlSafe), "state: \(first)")
    XCTAssertNotEqual(first, second)
  }
}
