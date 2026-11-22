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
  private var isolatedDefaults: IsolatedUserDefaults?

  override func setUp() async throws {
    try await super.setUp()
    isolatedDefaults = IsolatedUserDefaults(prefix: "VitalTelemetryHUDTests")
  }

  override func tearDown() async throws {
    isolatedDefaults?.tearDown()
    isolatedDefaults = nil
    try await super.tearDown()
  }

  func testVitalTelemetryHUD_Initialization() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let hud = VitalTelemetryHUD()
      .environment(PreferencesService(defaults: defaults))
    let host = UIHostingController(rootView: hud)
    XCTAssertNotNil(host.view)
  }

  func testVitalTelemetryHUD_RendersWithEmptyMetricsInUIHostingController() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let preferences = PreferencesService(defaults: defaults)
    preferences.activeTelemetryMetrics = []

    let hud = VitalTelemetryHUD()
      .environment(preferences)
    let host = UIHostingController(rootView: hud)

    XCTAssertNotNil(host.view)
  }

  func testVitalTelemetryHUD_RendersWithCompactSizeClassInUIHostingController() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let hud = VitalTelemetryHUD()
      .environment(\.horizontalSizeClass, .compact)
      .environment(PreferencesService(defaults: defaults))

    let host = UIHostingController(rootView: hud)
    XCTAssertNotNil(host.view)
  }

  func testVitalTelemetryHUD_RendersWithRegularSizeClassInUIHostingController() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let hud = VitalTelemetryHUD()
      .environment(\.horizontalSizeClass, .regular)
      .environment(PreferencesService(defaults: defaults))

    let host = UIHostingController(rootView: hud)
    XCTAssertNotNil(host.view)
  }
}
