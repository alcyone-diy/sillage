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
import CoreLocation
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

  func testVitalTelemetryHUD_RendersDirectlyWithDampingAndActiveNavigationServicesWithoutChartViewModel() async throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let preferences = PreferencesService(defaults: defaults)
    preferences.activeTelemetryMetrics = [.sog, .cog, .btw, .rng, .xte]

    let positioning = MockPositioningService()
    let dampingService = InstrumentDampingService(positioningService: positioning)
    dampingService.start()
    defer { dampingService.stop() }

    let db = try DatabaseManager.inMemory()
    let waypointService = WaypointService(databaseManager: db)
    let target = Waypoint(
      id: "hud-target",
      name: "HUD Target",
      coordinate: CLLocationCoordinate2D(latitude: 46.20, longitude: -1.20)
    )
    try await waypointService.saveWaypoint(target)

    let activeNavService = ActiveNavigationService(
      databaseManager: db,
      instrumentDampingService: dampingService
    )
    await activeNavService.start()
    defer { activeNavService.stop() }

    try await activeNavService.setDestination(waypointID: target.id)

    let hud = VitalTelemetryHUD()
      .environment(preferences)
      .environment(dampingService)
      .environment(activeNavService)

    let host = UIHostingController(rootView: hud)
    host.view.layoutIfNeeded()
    XCTAssertNotNil(host.view)
  }
}
