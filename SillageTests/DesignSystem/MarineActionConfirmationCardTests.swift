//
//  MarineActionConfirmationCardTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-08-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import SwiftUI
@testable import Sillage

@MainActor
final class MarineActionConfirmationCardTests: XCTestCase {

  func testInitialization_WithTitleString() {
    var confirmCalled = false
    var cancelCalled = false

    let card = MarineActionConfirmationCard(
      title: "Confirm position",
      onCancel: { cancelCalled = true },
      onConfirm: { confirmCalled = true }
    )

    XCTAssertNotNil(card)
    XCTAssertFalse(confirmCalled)
    XCTAssertFalse(cancelCalled)
  }

  func testInitialization_WithCustomHeaderContent() {
    var confirmCalled = false

    let card = MarineActionConfirmationCard(
      onConfirm: { confirmCalled = true }
    ) {
      Text("Custom Header Content")
        .font(.title)
    }

    XCTAssertNotNil(card)
    XCTAssertFalse(confirmCalled)
  }
}
