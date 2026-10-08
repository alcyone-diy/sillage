//
//  ChecklistCategoryItem+UI.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

extension ChecklistCategoryItem {
  func color(for theme: MarineTheme) -> Color {
    switch id {
    case "safety_emergency":
      return theme.colors.warning
    case "navigation_maneuver":
      return theme.colors.accent
    case "routine":
      return theme.colors.primary
    case "engine_technical":
      return theme.colors.textSecondary
    case "wintering_maintenance":
      return theme.colors.inactive
    default:
      return theme.colors.accent
    }
  }

  var displaySystemImage: String {
    if let icon, !icon.isEmpty {
      return icon
    }
    return "checklist"
  }
}
