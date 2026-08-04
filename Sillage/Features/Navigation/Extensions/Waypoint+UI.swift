//
//  Waypoint+UI.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

public extension Waypoint {
  var displayColor: Color {
    return Color(hex: validDisplayColorHex) ?? .blue
  }
  
  var validDisplayColorHex: String {
    if let hex = colorHex, Color(hex: hex) != nil {
      return hex
    }
    return Waypoint.defaultColorHex
  }
}
