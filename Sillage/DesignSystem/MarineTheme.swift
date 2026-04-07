//
//  MarineTheme.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct MarineTheme {
  let minTouchTarget: CGFloat
  let isGloveMode: Bool

  struct Colors {
    static let primary = Color.blue
    static let accent = Color.blue // Alias for primary, matching user request
    static let inactive = Color.gray
    static let warning = Color.yellow
    static let background = Color.black
    static let overlay = Color.black.opacity(0.3)
  }

  struct Spacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
  }

  struct MapMetrics {
    static let vesselCursorBaseSize = CGSize(width: 24, height: 36)
    static let headingLineWidth: Double = 2.5
  }

  static let standard = MarineTheme(minTouchTarget: 44, isGloveMode: false)
  static let gloveMode = MarineTheme(minTouchTarget: 66, isGloveMode: true)

  func fontSettings(for style: MarineTextStyle) -> (size: Font.TextStyle, weight: Font.Weight?) {
    switch style {
    case .largeTitle: return (.largeTitle, nil)
    case .title: return (.title, nil)
    case .title2: return (.title2, nil)
    case .title3: return (.title3, nil)
    case .headline: return (.headline, nil)
    case .body: return (.body, nil)
    case .callout: return (.callout, nil)
    case .subheadline: return (.subheadline, nil)
    case .footnote: return (.footnote, nil)
    case .caption: return (.caption, nil)
    case .caption2: return (.caption2, nil)
    case .instrumentData: return (.title3, .semibold)
    case .instrumentLabel: return (.headline, .bold)
    }
  }
}

private struct MarineThemeKey: EnvironmentKey {
  static let defaultValue: MarineTheme = .standard
}

extension EnvironmentValues {
  var marineTheme: MarineTheme {
    get { self[MarineThemeKey.self] }
    set { self[MarineThemeKey.self] = newValue }
  }
}
