//
//  ScreenshotScenario.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-14.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

#if DEBUG
import Foundation
import CoreLocation

/// Available presets for `--simulate-gps <sailing|anchorage>`.
enum SimulatedGPSPreset: String, Sendable, CaseIterable {
  /// Open-water sailing in Antioche Strait (`6.4 kts`, `COG 258°`) with a 1 NM leg origin for XTE/VMG.
  case sailing
  /// Vessel at anchor at Sablanceaux (Île de Ré) oscillating gently along a ~24 m swing arc (`0.2 kts`).
  case anchorage

  /// Resolves a CLI token (case-insensitive, supporting English and French aliases).
  static func resolve(from rawToken: String?) -> SimulatedGPSPreset {
    guard let token = rawToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !token.isEmpty else {
      return .sailing
    }
    switch token {
    case "anchorage", "anchor", "mouillage":
      return .anchorage
    case "sailing", "navigation", "default":
      return .sailing
    default:
      return .sailing
    }
  }
}

/// Available presets for `--simulate-baro <calm|storm>`.
enum SimulatedBaroPreset: String, Sendable, CaseIterable {
  /// Smooth, settled anticyclonic conditions (~1016–1020 hPa) with gentle semi-diurnal barometric tides.
  case calm
  /// Approaching Atlantic front with a marked pressure drop over the last 8 hours (~ -2.1 hPa / 3h).
  case storm

  /// Resolves a CLI token (case-insensitive, supporting English and French aliases).
  static func resolve(from rawToken: String?) -> SimulatedBaroPreset {
    guard let token = rawToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !token.isEmpty else {
      return .calm
    }
    switch token {
    case "storm", "front", "gale", "depression", "dramatic":
      return .storm
    case "calm", "anticyclone", "default":
      return .calm
    default:
      return .calm
    }
  }
}

/// Defines synthetic hardware sensor telemetry (GPS and/or Barometer) and optional demo tracks/waypoints
/// when launching the app with `--simulate-gps`, `--simulate-baro`, and/or `--simulate-tracks`.
/// User preferences (selected waypoint, camera, predictor vector, HUD configuration, alarms) are never modified.
struct ScreenshotScenario: Sendable {
  /// Returns the active `ScreenshotScenario` parsed from command-line arguments
  /// (disabled automatically inside the XCTest / Swift Testing harness unless explicitly injected).
  static var active: ScreenshotScenario? {
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
      return nil
    }
    return parse(from: CommandLine.arguments)
  }

  /// Returns `true` when any simulation flag (`--simulate-gps`, `--simulate-baro`, `--simulate-tracks`) is active.
  static var isEnabled: Bool {
    active != nil
  }

  /// Parses CLI arguments such as:
  /// - `["--simulate-gps", "sailing"]` or `["--simulate-gps=anchorage"]`
  /// - `["--simulate-baro", "calm"]` or `["--simulate-baro=storm"]`
  /// - `["--simulate-tracks"]` (seeds demo tracks and waypoints without changing user selection/preferences)
  /// - Legacy shorthand `["-screenshot-mode"]`, `["-screenshot-mode", "anchorage"]`, `["-screenshot-mode", "storm"]`
  static func parse(from arguments: [String]) -> ScreenshotScenario? {
    var gpsPreset: SimulatedGPSPreset?
    var baroPreset: SimulatedBaroPreset?
    var simulateTracksAndWaypoints = false

    for (index, arg) in arguments.enumerated() {
      let nextValue: String? = {
        let nextIndex = index + 1
        guard nextIndex < arguments.count else { return nil }
        let candidate = arguments[nextIndex]
        return candidate.hasPrefix("-") ? nil : candidate
      }()

      if arg == "--simulate-gps" || arg == "-simulate-gps" {
        gpsPreset = SimulatedGPSPreset.resolve(from: nextValue)
      } else if arg.hasPrefix("--simulate-gps=") || arg.hasPrefix("-simulate-gps=") {
        let value = arg.split(separator: "=", maxSplits: 1).dropFirst().first.map(String.init)
        gpsPreset = SimulatedGPSPreset.resolve(from: value)
      } else if arg == "--simulate-baro" || arg == "-simulate-baro" {
        baroPreset = SimulatedBaroPreset.resolve(from: nextValue)
      } else if arg.hasPrefix("--simulate-baro=") || arg.hasPrefix("-simulate-baro=") {
        let value = arg.split(separator: "=", maxSplits: 1).dropFirst().first.map(String.init)
        baroPreset = SimulatedBaroPreset.resolve(from: value)
      } else if arg == "--simulate-tracks" || arg == "-simulate-tracks"
        || arg == "--simulate-navigation" || arg == "-simulate-navigation" {
        simulateTracksAndWaypoints = true
      } else if arg == "--screenshot-mode" || arg == "-screenshot-mode" || arg == "-screeshot-mode" {
        let token = nextValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "storm" || token == "front" || token == "gale" || token == "depression" {
          gpsPreset = gpsPreset ?? .sailing
          baroPreset = baroPreset ?? .storm
        } else if token == "anchorage" || token == "anchor" || token == "mouillage" {
          gpsPreset = gpsPreset ?? .anchorage
          baroPreset = baroPreset ?? .calm
        } else {
          gpsPreset = gpsPreset ?? .sailing
          baroPreset = baroPreset ?? .calm
        }
        simulateTracksAndWaypoints = true
      } else if arg.hasPrefix("--screenshot-mode=") || arg.hasPrefix("-screenshot-mode=") || arg.hasPrefix("-screeshot-mode=") {
        let token = arg.split(separator: "=", maxSplits: 1).dropFirst().first.map {
          String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if token == "storm" || token == "front" || token == "gale" || token == "depression" {
          gpsPreset = gpsPreset ?? .sailing
          baroPreset = baroPreset ?? .storm
        } else if token == "anchorage" || token == "anchor" || token == "mouillage" {
          gpsPreset = gpsPreset ?? .anchorage
          baroPreset = baroPreset ?? .calm
        } else {
          gpsPreset = gpsPreset ?? .sailing
          baroPreset = baroPreset ?? .calm
        }
        simulateTracksAndWaypoints = true
      }
    }

    guard gpsPreset != nil || baroPreset != nil || simulateTracksAndWaypoints else {
      return nil
    }
    return scenario(
      gps: gpsPreset,
      baro: baroPreset,
      simulateTracksAndWaypoints: simulateTracksAndWaypoints
    )
  }

  let gpsPreset: SimulatedGPSPreset?
  let baroPreset: SimulatedBaroPreset?
  let simulateTracksAndWaypoints: Bool

  // MARK: - Vessel Telemetry (GPS, SOG, COG)

  /// Initial origin coordinate of the active GoTo leg (used to compute a realistic non-zero XTE).
  let legOriginCoordinate: CLLocationCoordinate2D

  /// Delay before transitioning from `legOriginCoordinate` to `vesselCoordinate` so `ActiveNavigationService`
  /// locks `originCoordinate` and computes a non-zero Cross-Track Error (`XTE`).
  var legOriginSettleDelay: Duration = .milliseconds(1150)

  /// Current vessel position on the chart.
  let vesselCoordinate: CLLocationCoordinate2D

  /// Sequence of coordinates traced back-and-forth during anchorage swing simulation (`[]` when sailing).
  let swingCoordinates: [CLLocationCoordinate2D]

  /// GPS horizontal accuracy radius.
  let horizontalAccuracy: Measurement<UnitLength>

  /// Speed Over Ground (SOG).
  let speedOverGround: Measurement<UnitSpeed>

  /// Course Over Ground (COG).
  let courseOverGround: Measurement<UnitAngle>

  // MARK: - Barometric Pressure & 7-Day Curve

  /// Current atmospheric pressure at sea level.
  let currentPressure: Measurement<UnitPressure>

  // MARK: - Device Battery

  /// Simulated battery level in [0.0, 1.0].
  let batteryLevel: Float

  // MARK: - Demo Waypoints (seeded only when `simulateTracksAndWaypoints` is true)

  let waypoints: [Waypoint]

  // MARK: - Scenario Factory

  /// Default combined scenario (`sailing` GPS + `calm` barometer + demo tracks/waypoints).
  static let `default`: ScreenshotScenario = scenario(
    gps: .sailing,
    baro: .calm,
    simulateTracksAndWaypoints: true
  )

  static func scenario(
    gps: SimulatedGPSPreset? = .sailing,
    baro: SimulatedBaroPreset? = .calm,
    simulateTracksAndWaypoints: Bool = false
  ) -> ScreenshotScenario {
    let resolvedGPS = gps ?? .sailing
    let resolvedBaro = baro ?? .calm

    let waypoints: [Waypoint] = [
      Waypoint(
        id: "screenshot-wpt-chauveau",
        name: "Chauveau Lighthouse",
        description: "South Île de Ré approach — South cardinal beacon",
        colorHex: "#FF9500",
        isVisible: true,
        coordinate: CLLocationCoordinate2D(latitude: 46.1336, longitude: -1.2739),
        timestamp: Date.now.addingTimeInterval(-3600 * 12)
      ),
      Waypoint(
        id: "screenshot-wpt-lavardin",
        name: "Lavardin Tower",
        description: "Isolated danger beacon — La Pallice channel",
        colorHex: "#007AFF",
        isVisible: true,
        coordinate: CLLocationCoordinate2D(latitude: 46.1347, longitude: -1.2425),
        timestamp: Date.now.addingTimeInterval(-3600 * 24)
      ),
      Waypoint(
        id: "screenshot-wpt-sablanceaux",
        name: "Sablanceaux Anchorage",
        description: "Sheltered from West to South-West winds, 4m sand bottom",
        colorHex: "#34C759",
        isVisible: true,
        coordinate: CLLocationCoordinate2D(latitude: 46.1625, longitude: -1.2680),
        timestamp: Date.now.addingTimeInterval(-3600 * 48)
      ),
      Waypoint(
        id: "screenshot-wpt-boyardville",
        name: "Boyardville Roads",
        description: "Perrotine channel approach — Île d'Oléron",
        colorHex: "#AF52DE",
        isVisible: true,
        coordinate: CLLocationCoordinate2D(latitude: 45.9750, longitude: -1.2250),
        timestamp: Date.now.addingTimeInterval(-3600 * 72)
      )
    ]

    let legOrigin: CLLocationCoordinate2D
    let vesselCoord: CLLocationCoordinate2D
    let swingArc: [CLLocationCoordinate2D]
    let accuracy: Measurement<UnitLength>
    let sog: Measurement<UnitSpeed>
    let cog: Measurement<UnitAngle>

    switch resolvedGPS {
    case .sailing:
      legOrigin = CLLocationCoordinate2D(latitude: 46.1400, longitude: -1.2000)
      vesselCoord = CLLocationCoordinate2D(latitude: 46.1365, longitude: -1.2150)
      swingArc = []
      accuracy = Measurement(value: 3.2, unit: .meters)
      sog = Measurement(value: 6.4, unit: .knots)
      cog = Measurement(value: 258.0, unit: .degrees)

    case .anchorage:
      let anchorCenter = CLLocationCoordinate2D(latitude: 46.1627, longitude: -1.2678)
      let arc = Self.makeAnchorageSwingArc(around: anchorCenter, radiusMeters: 24.0)
      legOrigin = anchorCenter
      vesselCoord = arc.first ?? CLLocationCoordinate2D(latitude: 46.1625, longitude: -1.2680)
      swingArc = arc
      accuracy = Measurement(value: 2.6, unit: .meters)
      sog = Measurement(value: 0.2, unit: .knots)
      cog = Measurement(value: 215.0, unit: .degrees)
    }

    let currentPressure: Measurement<UnitPressure> = switch resolvedBaro {
    case .calm:
      Measurement(value: 1018.4, unit: .hectopascals)
    case .storm:
      Measurement(value: 1009.2, unit: .hectopascals)
    }

    return ScreenshotScenario(
      gpsPreset: gps,
      baroPreset: baro,
      simulateTracksAndWaypoints: simulateTracksAndWaypoints,
      legOriginCoordinate: legOrigin,
      vesselCoordinate: vesselCoord,
      swingCoordinates: swingArc,
      horizontalAccuracy: accuracy,
      speedOverGround: sog,
      courseOverGround: cog,
      currentPressure: currentPressure,
      batteryLevel: 0.88,
      waypoints: waypoints
    )
  }

  /// Generates a 13-point curved swing arc (`~195°` to `255°` bearing at `radiusMeters` from `anchorCenter`),
  /// with each point spaced ~3.2 m apart so `AnchorService` records a clean swing arc on the chart.
  private static func makeAnchorageSwingArc(
    around anchorCenter: CLLocationCoordinate2D,
    radiusMeters: Double
  ) -> [CLLocationCoordinate2D] {
    let metersPerDegreeLat = 111_132.0
    let latRad = Measurement(value: anchorCenter.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let metersPerDegreeLon = 111_320.0 * cos(latRad)

    let pointCount = 13
    let startBearingDeg = 195.0
    let endBearingDeg = 255.0

    return (0..<pointCount).map { index in
      let fraction = Double(index) / Double(pointCount - 1)
      let bearingDeg = startBearingDeg + (endBearingDeg - startBearingDeg) * fraction
      let bearingRad = Measurement(value: bearingDeg, unit: UnitAngle.degrees).converted(to: .radians).value
      // Slight radial breathing (±1.5m) as gusts load and ease on the anchor rode
      let ripplePhase = Measurement(value: fraction * 360.0, unit: UnitAngle.degrees).converted(to: .radians).value
      let effectiveRadius = radiusMeters + 1.5 * sin(ripplePhase)

      let dNorthMeters = effectiveRadius * cos(bearingRad)
      let dEastMeters = effectiveRadius * sin(bearingRad)

      return CLLocationCoordinate2D(
        latitude: anchorCenter.latitude + (dNorthMeters / metersPerDegreeLat),
        longitude: anchorCenter.longitude + (dEastMeters / metersPerDegreeLon)
      )
    }
  }

  /// Generates 7 days of realistic barometric readings (every 4 minutes up to `referenceDate`,
  /// staying below `BarometerViewModel`'s 5-minute gap threshold so the chart renders a continuous curve).
  func makeBarometricHistory(referenceDate: Date = Date.now) -> [BarometricReading] {
    let profile = baroPreset ?? .calm
    let totalHours = 7 * 24
    let stepSeconds: TimeInterval = 240 // 4 minutes (< 300s segment gap threshold)
    let totalSteps = Int((Double(totalHours) * 3600.0) / stepSeconds)
    let endPressureHPa = currentPressure.converted(to: .hectopascals).value

    var readings: [BarometricReading] = []
    readings.reserveCapacity(totalSteps + 1)

    let rawAtPresent = Self.rawPressureProfile(hoursAgo: 0.0, profile: profile)
    let offsetToMatchTarget = endPressureHPa - rawAtPresent

    for step in stride(from: totalSteps, through: 0, by: -1) {
      let secondsAgo = Double(step) * stepSeconds
      let hoursAgo = secondsAgo / 3600.0
      let timestamp = referenceDate.addingTimeInterval(-secondsAgo)
      let hpa = Self.rawPressureProfile(hoursAgo: hoursAgo, profile: profile) + offsetToMatchTarget

      readings.append(
        BarometricReading(
          timestamp: timestamp,
          pressure: Measurement(value: hpa, unit: .hectopascals)
        )
      )
    }

    return readings
  }

  /// Synthetic meteorological pressure model as a function of `hoursAgo` (0 = now, 168 = 7 days ago).
  private static func rawPressureProfile(
    hoursAgo: Double,
    profile: SimulatedBaroPreset
  ) -> Double {
    switch profile {
    case .calm:
      // Settled anticyclonic regime: slow 4-day synoptic wave (±1.6 hPa) + gentle 12h barometric tide (±0.35 hPa)
      var pressure = 1018.0
      let synopticPhase = Measurement(value: (hoursAgo + 8.0) * 3.6, unit: UnitAngle.degrees).converted(to: .radians).value
      pressure += 1.6 * sin(synopticPhase)

      let secondaryPhase = Measurement(value: (hoursAgo - 6.0) * 6.0, unit: UnitAngle.degrees).converted(to: .radians).value
      pressure += 0.7 * cos(secondaryPhase)

      // Semi-diurnal atmospheric tide (12-hour period, ~0.35 hPa amplitude)
      let diurnalPhase = Measurement(value: hoursAgo * 30.0, unit: UnitAngle.degrees).converted(to: .radians).value
      pressure += 0.35 * sin(diurnalPhase)

      return pressure

    case .storm:
      var pressure = 1016.5
      let synopticPhase = Measurement(value: hoursAgo * 4.2, unit: UnitAngle.degrees).converted(to: .radians).value
      pressure += 4.2 * sin(synopticPhase)

      let secondaryPhase = Measurement(value: (hoursAgo - 12.0) * 9.5, unit: UnitAngle.degrees).converted(to: .radians).value
      pressure += 2.1 * cos(secondaryPhase)

      let diurnalPhase = Measurement(value: hoursAgo * 30.0, unit: UnitAngle.degrees).converted(to: .radians).value
      pressure += 0.65 * sin(diurnalPhase)

      // Approaching Atlantic front in the last 8 hours: smooth drop of ~5.2 hPa over 8 hours (~ -2.1 hPa / 3h)
      if hoursAgo < 8.0 {
        let progress = (8.0 - hoursAgo) / 8.0
        pressure -= 5.2 * (progress * progress)
      }

      return pressure
    }
  }
}
#endif
