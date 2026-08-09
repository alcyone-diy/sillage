//
//  VitalTelemetryHUDTests.swift
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
final class VitalTelemetryHUDTests: XCTestCase {

  func testVitalTelemetryHUD_Initialization() {
    let hud = VitalTelemetryHUD()
    let host = UIHostingController(rootView: hud)
    XCTAssertNotNil(host.view)
  }

  func testVitalTelemetryHUD_RendersInUIHostingController() {
    let hud = VitalTelemetryHUD()
    let host = UIHostingController(rootView: hud)

    XCTAssertNotNil(host.view)
  }

  func testVitalTelemetryHUD_RendersWithCompactSizeClassInUIHostingController() {
    let hud = VitalTelemetryHUD()
      .environment(\.horizontalSizeClass, .compact)

    let host = UIHostingController(rootView: hud)
    XCTAssertNotNil(host.view)
  }

  func testVitalTelemetryHUD_RendersWithRegularSizeClassInUIHostingController() {
    let hud = VitalTelemetryHUD()
      .environment(\.horizontalSizeClass, .regular)

    let host = UIHostingController(rootView: hud)
    XCTAssertNotNil(host.view)
  }
}
