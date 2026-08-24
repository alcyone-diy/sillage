//
//  TelemetryMetric.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Represents customizable telemetry metrics supported by the marine HUD overlay.
public enum TelemetryMetric: String, Codable, CaseIterable, Identifiable, Sendable {
  case sog
  case cog
  case btw
  case rng
  case xte
  case battery

  public var id: String { rawValue }

  /// Default localized label representation for each metric.
  public var label: LocalizedStringResource {
    switch self {
    case .sog: return LocalizedStringResource("SOG")
    case .cog: return LocalizedStringResource("COG")
    case .btw: return LocalizedStringResource("BTW")
    case .rng: return LocalizedStringResource("RNG")
    case .xte: return LocalizedStringResource("XTE")
    case .battery: return LocalizedStringResource("BATTERY")
    }
  }
}
