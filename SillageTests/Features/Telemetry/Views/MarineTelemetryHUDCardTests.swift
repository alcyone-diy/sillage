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

  func testHUDCardInitialization_WithDefaultHorizontalLayout() {
    let sogItem = MarineTelemetryItem(label: "SOG", value: "10.2 kn")
    let cogItem = MarineTelemetryItem(label: "COG", value: "180°")
    let card = MarineTelemetryHUDCard(items: [sogItem, cogItem])

    XCTAssertEqual(card.layout, .horizontal)

    let host = UIHostingController(rootView: card)
    XCTAssertNotNil(host.view)
  }

  func testHUDCardInitialization_WithExplicitHorizontalLayout() {
    let sogItem = MarineTelemetryItem(label: "SOG", value: "10.2 kn")
    let cogItem = MarineTelemetryItem(label: "COG", value: "180°")
    let card = MarineTelemetryHUDCard(items: [sogItem, cogItem], layout: .horizontal)

    XCTAssertEqual(card.layout, .horizontal)

    let host = UIHostingController(rootView: card)
    XCTAssertNotNil(host.view)
  }

  func testHUDCardInitialization_WithTwoColumnGridLayout() {
    let sogItem = MarineTelemetryItem(label: "SOG", value: "10.2 kn")
    let cogItem = MarineTelemetryItem(label: "COG", value: "180°")
    let card = MarineTelemetryHUDCard(items: [sogItem, cogItem], layout: .grid(columns: 2))

    XCTAssertEqual(card.layout, .grid(columns: 2))

    let host = UIHostingController(rootView: card)
    XCTAssertNotNil(host.view)
  }

  func testHUDCardInitialization_WithSingleColumnGridLayout() {
    let item = MarineTelemetryItem(label: "SOG", value: "12.0 kn")
    let card = MarineTelemetryHUDCard(items: [item], layout: .grid(columns: 1))

    XCTAssertEqual(card.layout, .grid(columns: 1))

    let host = UIHostingController(rootView: card)
    XCTAssertNotNil(host.view)
  }

  func testHUDCardInitialization_WithZeroOrNegativeGridColumns_FailsafeEvaluation() {
    let item = MarineTelemetryItem(label: "SOG", value: "12.0 kn")
    let cardZero = MarineTelemetryHUDCard(items: [item], layout: .grid(columns: 0))
    let cardNegative = MarineTelemetryHUDCard(items: [item], layout: .grid(columns: -2))

    XCTAssertEqual(cardZero.layout, .grid(columns: 0))
    XCTAssertEqual(cardNegative.layout, .grid(columns: -2))

    let hostZero = UIHostingController(rootView: cardZero)
    let hostNegative = UIHostingController(rootView: cardNegative)
    XCTAssertNotNil(hostZero.view)
    XCTAssertNotNil(hostNegative.view)
  }

  func testHUDCardInitialization_WithEmptyItems() {
    let emptyHorizontalCard = MarineTelemetryHUDCard(items: [], layout: .horizontal)
    let emptyGridCard = MarineTelemetryHUDCard(items: [], layout: .grid(columns: 2))

    let hostHorizontal = UIHostingController(rootView: emptyHorizontalCard)
    let hostGrid = UIHostingController(rootView: emptyGridCard)
    XCTAssertNotNil(hostHorizontal.view)
    XCTAssertNotNil(hostGrid.view)
  }
}
