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
  let baseStyle: Font.TextStyle
  @Environment(\.marineTheme) private var marineTheme

  func body(content: Content) -> some View {
    content.font(.system(effectiveStyle))
  }

  private var effectiveStyle: Font.TextStyle {
    guard marineTheme.isGloveMode else { return baseStyle }

    switch baseStyle {
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
      return baseStyle
    }
  }
}

extension View {
  func marineFont(_ baseStyle: Font.TextStyle) -> some View {
    self.modifier(MarineTextModifier(baseStyle: baseStyle))
  }
}
