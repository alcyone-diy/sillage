//
//  MarineTextModifier.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Applies a semantic `MarineTextStyle` to a view.
/// Typography relies exclusively on iOS Dynamic Type and is intentionally invariant to `isGloveMode`,
/// which governs motor ergonomics (touch targets, hit radii, gesture thresholds) rather than font sizing.
/// Passing `nil` returns `content` untouched (strict no-op) so inherited environment fonts are preserved.
struct MarineTextModifier: ViewModifier {
  let style: MarineTextStyle?

  @ViewBuilder
  func body(content: Content) -> some View {
    if let style {
      let settings = MarineTheme.fontSettings(for: style)

      if style == .instrumentData {
        content
          .font(.system(settings.size))
          .fontWeight(settings.weight)
          .monospacedDigit()
          .dynamicTypeSize(.large)
      } else if style == .instrumentLabel {
        content
          .font(.system(settings.size))
          .fontWeight(settings.weight)
          .dynamicTypeSize(.large)
      } else {
        content
          .font(.system(settings.size))
          .fontWeight(settings.weight)
      }
    } else {
      content
    }
  }
}

extension View {
  func marineFont(_ style: MarineTextStyle?) -> some View {
    self.modifier(MarineTextModifier(style: style))
  }

  func marineSectionHeader() -> some View {
    self
      .marineFont(.footnote)
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
  }
}
