//
//  DeveloperSettingsService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation

// MARK: - COG & SOG Calculation Source

public enum COGSOGCalculationSource: String, CaseIterable, Sendable {
  case sillage = "sillage"
  case iOS = "iOS"

  public var displayName: String {
    switch self {
    case .sillage: return "Sillage (GPS Positions)"
    case .iOS: return "iOS (CoreLocation)"
    }
  }
}

@Observable
@MainActor
final class DeveloperSettingsService {
  private let defaults: UserDefaults
  private let suiteName = "com.alcyonesillage.debug"

  private let cogSogCalculationSourceKey = "developer_cog_sog_calculation_source"
  private let noiseMultiplierKey = "developer_noise_multiplier"
  private let velocityWindowDurationKey = "developer_velocity_window_duration"
  private let cogDampingDurationKey = "developer_cog_damping_duration"
  private let pausesLocationUpdatesAutomaticallyKey = "developer_pauses_location_updates_automatically"

  private var rawCOGSOGCalculationSource: String {
    didSet { defaults.set(rawCOGSOGCalculationSource, forKey: cogSogCalculationSourceKey) }
  }

  private var rawNoiseMultiplier: Double {
    didSet { defaults.set(rawNoiseMultiplier, forKey: noiseMultiplierKey) }
  }

  private var rawVelocityWindowDuration: Double {
    didSet { defaults.set(rawVelocityWindowDuration, forKey: velocityWindowDurationKey) }
  }

  private var rawCOGDampingDuration: Double {
    didSet { defaults.set(rawCOGDampingDuration, forKey: cogDampingDurationKey) }
  }

  private var rawPausesLocationUpdatesAutomatically: Bool {
    didSet { defaults.set(rawPausesLocationUpdatesAutomatically, forKey: pausesLocationUpdatesAutomaticallyKey) }
  }

  var cogSogCalculationSource: COGSOGCalculationSource {
    get { COGSOGCalculationSource(rawValue: rawCOGSOGCalculationSource) ?? .sillage }
    set { rawCOGSOGCalculationSource = newValue.rawValue }
  }

  var noiseMultiplier: Double {
    get { rawNoiseMultiplier }
    set { rawNoiseMultiplier = newValue }
  }

  var velocityWindowDuration: TimeInterval {
    get { rawVelocityWindowDuration }
    set { rawVelocityWindowDuration = newValue }
  }

  var cogDampingDuration: TimeInterval {
    get { rawCOGDampingDuration }
    set { rawCOGDampingDuration = newValue }
  }

  var pausesLocationUpdatesAutomatically: Bool {
    get { rawPausesLocationUpdatesAutomatically }
    set { rawPausesLocationUpdatesAutomatically = newValue }
  }

  private let noiseMultiplierMigrationKey = "developer_noise_multiplier_migrated_v035"

  init(defaults: UserDefaults? = nil) {
    let resolvedDefaults = defaults ?? UserDefaults(suiteName: "com.alcyonesillage.debug") ?? .standard
    self.defaults = resolvedDefaults

    self.rawCOGSOGCalculationSource = resolvedDefaults.string(forKey: cogSogCalculationSourceKey) ?? COGSOGCalculationSource.sillage.rawValue

    let hasMigrated = resolvedDefaults.bool(forKey: noiseMultiplierMigrationKey)
    if !hasMigrated {
      // Migrate old default 1.0 (or unset) to optimal 0.35
      self.rawNoiseMultiplier = 0.35
      resolvedDefaults.set(true, forKey: noiseMultiplierMigrationKey)
    } else {
      self.rawNoiseMultiplier = resolvedDefaults.object(forKey: noiseMultiplierKey) as? Double ?? 0.35
    }

    self.rawVelocityWindowDuration = resolvedDefaults.object(forKey: velocityWindowDurationKey) as? Double ?? 4.0
    self.rawCOGDampingDuration = resolvedDefaults.object(forKey: cogDampingDurationKey) as? Double ?? 4.0
    self.rawPausesLocationUpdatesAutomatically = resolvedDefaults.bool(forKey: pausesLocationUpdatesAutomaticallyKey)
  }

  func resetAllToDefaults() {
    defaults.removePersistentDomain(forName: suiteName)
    self.rawCOGSOGCalculationSource = COGSOGCalculationSource.sillage.rawValue
    self.rawNoiseMultiplier = 0.35
    self.rawVelocityWindowDuration = 4.0
    self.rawCOGDampingDuration = 4.0
    self.rawPausesLocationUpdatesAutomatically = false
  }
}
