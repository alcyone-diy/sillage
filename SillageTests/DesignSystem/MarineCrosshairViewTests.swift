//
//  MarineCrosshairViewTests.swift
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
final class MarineCrosshairViewTests: XCTestCase {

  func testInitialization_WithDefaultParameters() {
    let crosshair = MarineCrosshairView()
    XCTAssertEqual(crosshair.size, 44)
    XCTAssertNil(crosshair.color)
    XCTAssertNil(crosshair.centerDotColor)
  }

  func testInitialization_WithCustomParameters() {
    let customColor = Color.red
    let customDotColor = Color.yellow
    let crosshair = MarineCrosshairView(size: 60, color: customColor, centerDotColor: customDotColor)

    XCTAssertEqual(crosshair.size, 60)
    XCTAssertEqual(crosshair.color, customColor)
    XCTAssertEqual(crosshair.centerDotColor, customDotColor)
  }
}
