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
}
