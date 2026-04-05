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
  @Environment(\.marineTheme) private var marineTheme
  let baseStyle: Font.TextStyle

  func body(content: Content) -> some View {
    content
      .font(.system(scaledStyle))
  }

  private var scaledStyle: Font.TextStyle {
    guard marineTheme.isGloveMode else {
      return baseStyle
    }

    switch baseStyle {
    case .largeTitle: return .largeTitle // No larger available
    case .title: return .largeTitle
    case .title2: return .title
    case .title3: return .title2
    case .headline: return .title3
    case .body: return .title3
    case .callout: return .body
    case .subheadline: return .headline
    case .footnote: return .subheadline
    case .caption: return .subheadline
    case .caption2: return .caption
    @unknown default:
      return baseStyle
    }
  }
}

extension View {
  func marineFont(_ baseStyle: Font.TextStyle) -> some View {
    self.modifier(MarineTextModifier(baseStyle: baseStyle))
  }
}
