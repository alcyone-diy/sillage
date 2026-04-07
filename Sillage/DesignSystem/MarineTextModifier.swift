//
//  MarineTextModifier.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct MarineTextModifier: ViewModifier {
  let style: MarineTextStyle
  @Environment(\.marineTheme) private var marineTheme

  @ViewBuilder
  func body(content: Content) -> some View {
    let settings = marineTheme.fontSettings(for: style)
    let effectiveStyle = (style == .instrumentData) ? settings.size : calculateEffectiveStyle(base: settings.size)

    if style == .instrumentData {
      content
        .font(.system(effectiveStyle))
        .fontWeight(settings.weight)
        .monospacedDigit()
        .dynamicTypeSize(.large)
    } else {
      content
        .font(.system(effectiveStyle))
        .fontWeight(settings.weight)
    }
  }

  private func calculateEffectiveStyle(base: Font.TextStyle) -> Font.TextStyle {
    guard marineTheme.isGloveMode else { return base }

    switch base {
    case .caption, .caption2:
      return .subheadline
    case .subheadline, .footnote:
      return .body
    case .body, .callout:
      return .title3
    case .title3:
      return .title2
    case .title2:
      return .title
    case .title:
      return .largeTitle
    default:
      return base
    }
  }
}

extension View {
  func marineFont(_ style: MarineTextStyle) -> some View {
    self.modifier(MarineTextModifier(style: style))
  }
}
