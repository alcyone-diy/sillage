//
//  TelemetryPreferences.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

/// Persistence store managing user-selected active HUD telemetry metrics.
@Observable
@MainActor
public final class TelemetryPreferences {
  public static let defaultMetrics: [TelemetryMetric] = [.sog, .cog, .btw, .rng]
  private static let userDefaultsKey = "sillage.telemetry.activeMetrics"

  private let userDefaults: UserDefaults

  public var activeMetrics: [TelemetryMetric] {
    didSet {
      saveActiveMetrics()
    }
  }

  public init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    if let data = userDefaults.data(forKey: Self.userDefaultsKey),
       let decoded = try? JSONDecoder().decode([TelemetryMetric].self, from: data),
       !decoded.isEmpty {
      self.activeMetrics = decoded
    } else {
      self.activeMetrics = Self.defaultMetrics
    }
  }

  private func saveActiveMetrics() {
    if let encoded = try? JSONEncoder().encode(activeMetrics) {
      userDefaults.set(encoded, forKey: Self.userDefaultsKey)
    }
  }

  /// Resets active metrics to default configuration.
  public func resetToDefaults() {
    activeMetrics = Self.defaultMetrics
  }
}
