//
//  ChecklistCategory.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Defines maritime procedural categories for nautical checklists.
public enum ChecklistCategory: String, Codable, Sendable, CaseIterable {
  case safetyEmergency = "safety_emergency"
  case navigationManeuver = "navigation_maneuver"
  case routine = "routine"
  case engineTechnical = "engine_technical"
  case winteringMaintenance = "wintering_maintenance"

  nonisolated public var title: String {
    switch self {
    case .safetyEmergency:
      return "Safety & Emergency"
    case .navigationManeuver:
      return "Navigation & Maneuver"
    case .routine:
      return "Routine"
    case .engineTechnical:
      return "Engine & Technical"
    case .winteringMaintenance:
      return "Wintering & Maintenance"
    }
  }

  nonisolated public var systemImage: String {
    switch self {
    case .safetyEmergency:
      return "exclamationmark.shield.fill"
    case .navigationManeuver:
      return "steeringwheel"
    case .routine:
      return "checklist"
    case .engineTechnical:
      return "wrench.and.screwdriver.fill"
    case .winteringMaintenance:
      return "snowflake"
    }
  }
}
