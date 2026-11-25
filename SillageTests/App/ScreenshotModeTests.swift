//
//  ScreenshotModeTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-14.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

#if DEBUG
import Testing
import Foundation
import CoreLocation
@testable import Sillage

@MainActor
@Suite("Sensor Simulation (-simulate-gps & -simulate-baro) Tests", .serialized)
struct ScreenshotModeTests {

  @Test("Sensor simulation populates GPS, COG, SOG, XTE, Barometer graph, and Battery without altering user preferences")
  func testScreenshotModeFullTelemetryHydration() async throws {
    TileProxyProtocol.resetForTesting()
    MockURLProtocol.reset()
    MockURLProtocol.setHandler { request in
      let url = request.url ?? URL(fileURLWithPath: "/")
      let response = HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil) ?? HTTPURLResponse()
      return (response, Data())
    }

    let authSession = MockURLProtocol.makeMockSession()
    let partnerSecretService = MockGeoGaragePartnerSecretService()
    let mockKeychain = MockKeychainManager()
    let isolatedDefaults = IsolatedUserDefaults(prefix: "ScreenshotModeTests")
    defer {
      isolatedDefaults.tearDown()
      MockURLProtocol.reset()
      TileProxyProtocol.resetForTesting()
    }

    let dbManager = try DatabaseManager.inMemory()

    // Seed a user waypoint and user preferences before launching with simulated sensors
    let userWaypoint = Waypoint(
      id: "user-wpt-chauveau",
      name: "Chauveau Lighthouse",
      description: "South Île de Ré approach",
      colorHex: "#FF9500",
      isVisible: true,
      coordinate: CLLocationCoordinate2D(latitude: 46.1336, longitude: -1.2739),
      timestamp: Date.now.addingTimeInterval(-3600)
    )
    try await WaypointService(databaseManager: dbManager).saveWaypoint(userWaypoint)
    isolatedDefaults.defaults.set("user-wpt-chauveau", forKey: "goToWaypointID")
    isolatedDefaults.defaults.set(false, forKey: "isCOGVectorEnabled")
    isolatedDefaults.defaults.set(1800.0, forKey: "cogVectorTimeHorizonSeconds")

    var scenario = ScreenshotScenario.default
    scenario.legOriginSettleDelay = .milliseconds(50)

    var overrides = try makeTestOverrides(userDefaults: isolatedDefaults.defaults)
    overrides.partnerSecretService = partnerSecretService
    overrides.authSession = authSession
    overrides.keychainManager = mockKeychain
    overrides.useDatabaseManager(dbManager)
    // Leave `positioningService` unset so `bootstrap()` selects `SimulatedPositioningService(scenario:)`.
    overrides.positioningService = nil
    overrides.screenshotScenario = scenario

    let env = AppEnvironment(overrides: overrides)

    await env.bootstrap()

    guard case .ready(let container) = env.state else {
      Issue.record("AppEnvironment failed to reach .ready in sensor simulation mode")
      return
    }

    // 0. User preferences (predictor vector, selected waypoint, HUD metrics, disclaimer) must remain 100% untouched
    #expect(container.preferencesService.goToWaypointID == "user-wpt-chauveau")
    #expect(container.preferencesService.isCOGVectorEnabled == false)
    #expect(container.preferencesService.cogVectorTimeHorizon == Measurement(value: 1800.0, unit: .seconds))
    #expect(isolatedDefaults.defaults.object(forKey: "hasAcceptedDisclaimer") == nil)
    #expect(isolatedDefaults.defaults.object(forKey: "sillage.telemetry.activeMetrics") == nil)

    // 1. Permissions should all be forced to .authorized
    #expect(container.permissionService.locationStatus == .authorized)
    #expect(container.permissionService.motionStatus == .authorized)
    #expect(container.permissionService.notificationStatus == .authorized)

    // 2. Wait for the initial leg origin fix + vessel fix to settle
    for _ in 0..<40 {
      if let coord = container.chartViewModel.currentCoordinate,
         abs(coord.latitude - scenario.vesselCoordinate.latitude) < 0.0001,
         container.chartViewModel.crossTrackError != nil,
         container.barometerViewModel.formattedTrend != nil {
        break
      }
      try? await Task.sleep(for: .milliseconds(50))
    }

    // 3. Verify GPS, SOG, COG, BTW, RNG, XTE on ChartViewModel
    let currentCoord = try #require(container.chartViewModel.currentCoordinate)
    #expect(abs(currentCoord.latitude - scenario.vesselCoordinate.latitude) < 0.0001)
    #expect(abs(currentCoord.longitude - scenario.vesselCoordinate.longitude) < 0.0001)

    let sogKnots = try #require(container.chartViewModel.smoothedSOG?.converted(to: .knots).value)
    #expect(abs(sogKnots - 6.4) < 0.05)

    let cogDegrees = try #require(container.chartViewModel.smoothedCOG?.normalizedDegrees)
    #expect(abs(cogDegrees - 258.0) < 0.5)

    #expect(container.chartViewModel.bearingToWaypoint != nil)
    #expect(container.chartViewModel.rangeToWaypoint != nil)
    let xteNM = try #require(container.chartViewModel.crossTrackError?.converted(to: .marineNauticalMiles).value)
    #expect(abs(xteNM) > 0.001)

    // 4. Verify user's Waypoint + 4 seeded demo Waypoints and 2 seeded demo Tracks, with user's Active GoTo preserved
    #expect(container.waypointService.currentWaypoints.count == 5)
    #expect(container.waypointService.goToWaypointID == "user-wpt-chauveau")
    var observedTracks: [TrackSession] = []
    for await sessions in container.trackService.observeTrackSessions() {
      observedTracks = sessions
      break
    }
    #expect(observedTracks.count == 2)

    // 5. Verify Barometer pressure, 3h trend, and continuous 7-day chart history (single connected segment)
    #expect(container.barometerViewModel.formattedPressure != nil)
    #expect(container.barometerViewModel.formattedTrend != nil)
    #expect(container.barometerViewModel.chartData.count > 2500)
    #expect(Set(container.barometerViewModel.chartData.map(\.segmentId)).count == 1)

    // 6. Verify Device Battery in SecondaryTelemetryViewModel
    let batteryItem = container.secondaryTelemetryViewModel.items.first(where: { $0.id == "BATTERY" })
    #expect(batteryItem?.value == "88%")
    #expect(batteryItem?.isPlaceholder == false)

    // 7. Verify cleanup removes only seeded demo tracks/waypoints while keeping user-created waypoints intact
    try await ScreenshotBootstrapper.removeSeededTracksAndWaypoints(from: dbManager)
    let remainingWaypoints = try await container.waypointService.fetchWaypoints()
    #expect(remainingWaypoints.map(\.id) == ["user-wpt-chauveau"])
    var remainingTracks: [TrackSession] = []
    for await sessions in container.trackService.observeTrackSessions() {
      remainingTracks = sessions
      break
    }
    #expect(remainingTracks.isEmpty)
  }

  @Test("CLI parser supports independent -simulate-gps and -simulate-baro flags")
  func testPresetParsingAndAnchorageScenario() {
    #expect(ScreenshotScenario.parse(from: ["Sillage"]) == nil)

    // Independent -simulate-gps
    let gpsSailingOnly = ScreenshotScenario.parse(from: ["Sillage", "-simulate-gps", "sailing"])
    #expect(gpsSailingOnly?.gpsPreset == .sailing)
    #expect(gpsSailingOnly?.baroPreset == nil)

    let gpsAnchorageOnly = ScreenshotScenario.parse(from: ["Sillage", "-simulate-gps", "anchorage"])
    #expect(gpsAnchorageOnly?.gpsPreset == .anchorage)
    #expect(gpsAnchorageOnly?.baroPreset == nil)
    #expect(gpsAnchorageOnly?.swingCoordinates.count == 13)

    let gpsMouillageAlias = ScreenshotScenario.parse(from: ["Sillage", "-simulate-gps=mouillage"])
    #expect(gpsMouillageAlias?.gpsPreset == .anchorage)
    #expect(gpsMouillageAlias?.baroPreset == nil)

    // Independent -simulate-baro
    let baroCalmOnly = ScreenshotScenario.parse(from: ["Sillage", "-simulate-baro", "calm"])
    #expect(baroCalmOnly?.gpsPreset == nil)
    #expect(baroCalmOnly?.baroPreset == .calm)

    let baroStormOnly = ScreenshotScenario.parse(from: ["Sillage", "-simulate-baro", "storm"])
    #expect(baroStormOnly?.gpsPreset == nil)
    #expect(baroStormOnly?.baroPreset == .storm)

    // Combined --simulate-gps, --simulate-baro, and --simulate-tracks (both -- and - supported)
    let combined = ScreenshotScenario.parse(from: [
      "Sillage",
      "--simulate-gps", "anchorage",
      "--simulate-baro", "storm",
      "--simulate-tracks"
    ])
    #expect(combined?.gpsPreset == .anchorage)
    #expect(combined?.baroPreset == .storm)
    #expect(combined?.simulateTracksAndWaypoints == true)

    let tracksOnly = ScreenshotScenario.parse(from: ["Sillage", "--simulate-tracks"])
    #expect(tracksOnly?.gpsPreset == nil)
    #expect(tracksOnly?.baroPreset == nil)
    #expect(tracksOnly?.simulateTracksAndWaypoints == true)
  }
}
#endif
