//
//  VitalTelemetryOverlayTests.swift
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
final class VitalTelemetryOverlayTests: XCTestCase {

  func testVitalTelemetryOverlay_Initialization() {
    let overlay = VitalTelemetryOverlay()
    let host = UIHostingController(rootView: overlay)
    XCTAssertNotNil(host.view)
  }

  func testVitalTelemetryOverlay_RendersInUIHostingController() {
    let overlay = VitalTelemetryOverlay()
    let host = UIHostingController(rootView: overlay)

    XCTAssertNotNil(host.view)
  }

  func testVitalTelemetryOverlay_RendersWithCompactSizeClassInUIHostingController() {
    let overlay = VitalTelemetryOverlay()
      .environment(\.horizontalSizeClass, .compact)

    let host = UIHostingController(rootView: overlay)
    XCTAssertNotNil(host.view)
  }

  func testVitalTelemetryOverlay_RendersWithRegularSizeClassInUIHostingController() {
    let overlay = VitalTelemetryOverlay()
      .environment(\.horizontalSizeClass, .regular)

    let host = UIHostingController(rootView: overlay)
    XCTAssertNotNil(host.view)
  }
}
