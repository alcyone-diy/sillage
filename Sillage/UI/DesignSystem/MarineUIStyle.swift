//
//  MarineUIStyle.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Defines the global interaction mode of the application.
/// `gloveMode` increases touch target sizes (minimum 66pt)
/// and scales standard typography for use in degraded conditions (cold, moisture, wearing gloves).
enum MarineUIStyle {
  case standard
  case gloveMode
}

/// The Single Source of Truth for "Sillage" typography.
/// Views must NEVER use `Font.system()` directly; they must always route through the `.marineFont()` modifier.
enum MarineTextStyle {
  // MARK: - Standard Semantic Styles (Apple)
  // These styles react dynamically to `MarineUIStyle` (Glove Mode)
  // and the iPad's accessibility settings (Dynamic Type).
  case largeTitle
  case title
  case title2
  case title3
  case headline
  case body
  case callout
  case subheadline
  case footnote
  case caption
  case caption2

  // MARK: - Marine Domain Specific Styles (HUD)
  // These styles are STRICTLY LOCKED and immune to "Glove Mode" or Dynamic Type scaling
  // to ensure the structural integrity of the navigation grid (Head-Up Display).

  /// Used for dynamic sensor values (e.g., "12.4 kts", "345°").
  /// Automatically implements `.monospacedDigit()` to prevent horizontal visual jitter.
  case instrumentData

  /// Used for static descriptive labels (e.g., "SOG", "COG").
  /// Maintains a small size to prioritize the readability of the associated data.
  case instrumentLabel
}
