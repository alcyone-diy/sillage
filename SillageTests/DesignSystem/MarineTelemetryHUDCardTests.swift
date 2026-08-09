//
//  MarineTelemetryHUDCardTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import SwiftUI
@testable import Sillage

@MainActor
final class MarineTelemetryHUDCardTests: XCTestCase {

  func testItemInitialization_WithDefaultParameters() {
    let item = MarineTelemetryItem(label: "SOG", value: "5.4 kn")
    XCTAssertEqual(item.id, "SOG")
    XCTAssertEqual(item.label.key, "SOG")
    XCTAssertEqual(item.value, "5.4 kn")
    XCTAssertFalse(item.isPlaceholder)
  }

  func testItemInitialization_WithCustomParameters() {
    let item = MarineTelemetryItem(id: "custom-id", label: "DISTANCE", value: "---", isPlaceholder: true)
    XCTAssertEqual(item.id, "custom-id")
    XCTAssertEqual(item.label.key, "DISTANCE")
    XCTAssertEqual(item.value, "---")
    XCTAssertTrue(item.isPlaceholder)
  }

  func testHUDCardInitialization_WithTelemetryItems() {
    let sogItem = MarineTelemetryItem(label: "SOG", value: "10.2 kn")
    let cogItem = MarineTelemetryItem(label: "COG", value: "180°")
    let card = MarineTelemetryHUDCard(items: [sogItem, cogItem])

    XCTAssertNotNil(card.body)
  }
}
