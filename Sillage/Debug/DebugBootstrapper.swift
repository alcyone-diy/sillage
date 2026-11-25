//
//  DebugBootstrapper.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

#if DEBUG
import Foundation
import Observation
import OSLog

/// Isolates debug-only bootstrap wiring (`ScreenshotScenario` seeding/simulation and
/// `DeveloperSettingsService` bindings) from `AppEnvironment.bootstrap()`.
@MainActor
enum DebugBootstrapper {

  /// Resolves the active screenshot scenario (override first, then launch arguments) and logs it.
  static func resolveScenario(override: ScreenshotScenario?) -> ScreenshotScenario? {
    let scenario = override ?? ScreenshotScenario.active
    if let scenario {
      let gpsLabel = scenario.gpsPreset?.rawValue ?? "off"
      let baroLabel = scenario.baroPreset?.rawValue ?? "off"
      Logger.system.notice("📸 Sensor simulation active (gps=\(gpsLabel, privacy: .public), baro=\(baroLabel, privacy: .public), tracks=\(scenario.simulateTracksAndWaypoints, privacy: .public)). User preferences remain untouched.")
    }
    return scenario
  }

  /// Phase 1 helper: seeds or cleans demo tracks/waypoints and prepares the barometric database.
  static func prepareDatabases(
    scenario: ScreenshotScenario?,
    databaseManager: DatabaseManager,
    hasCustomDatabaseFactory: Bool
  ) async throws -> DatabaseManager {
    if let scenario, scenario.simulateTracksAndWaypoints {
      try await ScreenshotBootstrapper.seedTracksAndWaypoints(scenario, into: databaseManager)
    } else {
      try await ScreenshotBootstrapper.removeSeededTracksAndWaypoints(from: databaseManager)
    }

    if let scenario, scenario.baroPreset != nil {
      if hasCustomDatabaseFactory {
        try await ScreenshotBootstrapper.seedBarometricHistory(scenario, into: databaseManager)
        return databaseManager
      } else {
        return try await ScreenshotBootstrapper.makeBarometricDatabase(scenario: scenario)
      }
    }
    return databaseManager
  }

  /// Creates `DeveloperSettingsService` using ephemeral defaults when GPS simulation is active
  /// so screenshot presets never overwrite the user's real developer settings.
  static func makeDeveloperSettingsService(
    scenario: ScreenshotScenario?,
    userDefaults: UserDefaults
  ) -> DeveloperSettingsService {
    let devSettingsDefaults: UserDefaults? = {
      guard scenario?.gpsPreset != nil else { return nil }
      let suiteName = "com.alcyone.sillage.simulated.devsettings"
      let ephemeralDefaults = UserDefaults(suiteName: suiteName)
      ephemeralDefaults?.removePersistentDomain(forName: suiteName)
      return ephemeralDefaults
    }()
    let developerSettingsService = DeveloperSettingsService(defaults: devSettingsDefaults ?? userDefaults)
    if scenario?.gpsPreset != nil {
      developerSettingsService.cogSogCalculationSource = .iOS
      developerSettingsService.cogDampingDuration = 0.0
    }
    return developerSettingsService
  }

  static func makeSimulatedPositioningService(
    scenario: ScreenshotScenario?
  ) -> (any PositioningService)? {
    guard let scenario, scenario.gpsPreset != nil else { return nil }
    return SimulatedPositioningService(scenario: scenario)
  }

  static func makeSimulatedAltimeterProvider(
    scenario: ScreenshotScenario?
  ) -> (any AltimeterProvider)? {
    guard let scenario, scenario.baroPreset != nil else { return nil }
    return SimulatedAltimeterProvider(scenario: scenario)
  }

  static func makeSimulatedBatteryService(
    scenario: ScreenshotScenario?
  ) -> (any DeviceBatteryServiceProtocol)? {
    scenario.map { SimulatedBatteryService(scenario: $0) }
  }

  static func applySimulatedPermissions(
    scenario: ScreenshotScenario?,
    to permissionService: PermissionService
  ) {
    guard let scenario else { return }
    permissionService.forceAuthorizedForSimulatedSensors(
      gps: scenario.gpsPreset != nil,
      baro: scenario.baroPreset != nil
    )
  }

  static func refreshSimulatedBarometerIfNeeded(
    scenario: ScreenshotScenario?,
    barometerViewModel: BarometerViewModel
  ) async {
    guard let scenario, scenario.baroPreset != nil else { return }
    await barometerViewModel.refreshFullHistory()
  }

  /// Applies initial developer settings and observes runtime changes onto kinematics and damping.
  static func bindDeveloperSettings<C: Clock & Sendable>(
    _ developerSettingsService: DeveloperSettingsService,
    to kinematicsService: VesselKinematicsService,
    dampingService: InstrumentDampingService<C>
  ) where C.Duration == Duration {
    applyDeveloperSettings(
      developerSettingsService,
      to: kinematicsService,
      dampingService: dampingService
    )
    observeDeveloperSettings(
      developerSettingsService: developerSettingsService,
      kinematicsService: kinematicsService,
      instrumentDampingService: dampingService
    )
  }

  private static func applyDeveloperSettings<C: Clock & Sendable>(
    _ settings: DeveloperSettingsService,
    to kinematicsService: VesselKinematicsService,
    dampingService: InstrumentDampingService<C>
  ) where C.Duration == Duration {
    kinematicsService.calculationSource = settings.cogSogCalculationSource
    kinematicsService.noiseMultiplier = settings.noiseMultiplier
    kinematicsService.velocityWindowDuration = settings.velocityWindowDuration
    dampingService.cogDampingDuration = settings.cogDampingDuration
  }

  private static func observeDeveloperSettings<C: Clock & Sendable>(
    developerSettingsService: DeveloperSettingsService,
    kinematicsService: VesselKinematicsService,
    instrumentDampingService: InstrumentDampingService<C>
  ) where C.Duration == Duration {
    withObservationTracking {
      _ = developerSettingsService.cogSogCalculationSource
      _ = developerSettingsService.noiseMultiplier
      _ = developerSettingsService.velocityWindowDuration
      _ = developerSettingsService.cogDampingDuration
    } onChange: { [weak kinematicsService, weak instrumentDampingService, weak developerSettingsService] in
      Task { @MainActor [weak kinematicsService, weak instrumentDampingService, weak developerSettingsService] in
        guard let settings = developerSettingsService,
              let kinematics = kinematicsService,
              let damping = instrumentDampingService else { return }
        applyDeveloperSettings(settings, to: kinematics, dampingService: damping)
        observeDeveloperSettings(
          developerSettingsService: settings,
          kinematicsService: kinematics,
          instrumentDampingService: damping
        )
      }
    }
  }
}
#endif
