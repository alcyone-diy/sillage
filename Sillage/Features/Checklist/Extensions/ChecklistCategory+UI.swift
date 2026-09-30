//
//  ChecklistCategory+UI.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

extension ChecklistCategory {
  func color(for theme: MarineTheme) -> Color {
    switch self {
    case .safetyEmergency:
      return theme.colors.warning
    case .navigationManeuver:
      return theme.colors.accent
    case .routine:
      return theme.colors.primary
    case .engineTechnical:
      return theme.colors.textSecondary
    case .winteringMaintenance:
      return theme.colors.inactive
    }
  }
}
