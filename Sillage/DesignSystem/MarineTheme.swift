//
//  MarineTheme.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct MarineTheme {
  let minTouchTarget: CGFloat
  let isGloveMode: Bool
  let colors: Colors

  struct Colors {
    let primary: Color
    let inactive: Color
    let warning: Color
    let cancelAction: Color
    let background: Color
    let overlay: Color
    let shadow: Color
    
    let surfaceBackground: Color
    let activeToggle: Color
    let textOnActive: Color
    let onPrimary: Color
    let textPrimary: Color
    let textSecondary: Color
    let panelBackground: Color
    let secondarySurface: Color
    let destructive: Color
    let destructiveBackground: Color
    let disabledBackground: Color
    let border: Color

    // Marine Navigation Vectors
    let vectorCOG: Color
    let vectorHDG: Color
    let vectorTick: Color
    
    // Anchor & Safety
    let anchorArmed: Color
    let anchorDragging: Color
    let anchorDropped: Color

    // Computed properties for derived colors and aliases
    var accent: Color { primary }
    var error: Color { destructive }
    var primaryFaded: Color { primary.opacity(0.4) }
    var planningLine: Color { primary.opacity(0.5) }
  }
  
  static let dayColors = Colors(
    primary: .blue,
    inactive: .gray,
    warning: .yellow,
    cancelAction: .orange,
    background: .black,
    overlay: Color.black.opacity(0.3),
    shadow: Color.black.opacity(0.1),
    surfaceBackground: Color(uiColor: .secondarySystemGroupedBackground),
    activeToggle: .cyan,
    textOnActive: .white,
    onPrimary: .white,
    textPrimary: .primary,
    textSecondary: .secondary,
    panelBackground: Color(uiColor: .systemGroupedBackground),
    secondarySurface: Color(uiColor: .secondarySystemGroupedBackground),
    destructive: Color(uiColor: .systemRed),
    destructiveBackground: Color(uiColor: .systemRed).opacity(0.15),
    disabledBackground: Color.gray.opacity(0.15),
    border: Color(uiColor: .separator),
    vectorCOG: Color(red: 1.0, green: 0.0, blue: 1.0), // Magenta
    vectorHDG: Color(UIColor { traitCollection in
      traitCollection.userInterfaceStyle == .dark ? .systemYellow : .darkGray
    }), // Amber for dark mode, dark gray for light mode
    vectorTick: .black,
    anchorArmed: Color(uiColor: .systemGreen), // Will be adapted for night mode later
    anchorDragging: Color(uiColor: .systemRed),
    anchorDropped: Color(red: 0.0, green: 1.0, blue: 1.0) // Cyan #00FFFF
  )

  struct Metrics {
    let touchTarget: CGFloat
    
    /// The visual size of the interaction handles, dynamically adjusted for Glove Mode visibility.
    let handleSize: CGFloat
    static let cornerRadius: CGFloat = 12.0
    static let borderWidth: CGFloat = 1.0
    static let paginationDotSize: CGFloat = 6.0
    static let shadowRadius: CGFloat = 4.0
    static let shadowOffset: CGFloat = 2.0
  }

  var metrics: Metrics {
    Metrics(touchTarget: minTouchTarget, handleSize: isGloveMode ? 36.0 : 24.0)
  }

  struct Spacing {
    static let tiny: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 32
  }

  struct ChartMetrics {
    static let vesselCursorBaseSize = CGSize(width: 24, height: 36)
    static let headingLineWidth: Double = 2.5
    static let planningLineWidth: Double = 1.0
    static let gpsAccuracyFillOpacity: Double = 0.15
    static let gpsAccuracyStrokeOpacity: Double = 0.4
    static let gpsAccuracyLineWidth: Double = 1.0
  }

  static let standard = MarineTheme(minTouchTarget: 44, isGloveMode: false, colors: dayColors)
  static let gloveMode = MarineTheme(minTouchTarget: 66, isGloveMode: true, colors: dayColors)

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

public extension View {
  /// Adds a small red badge indicator to the top-trailing corner of the view when `isPresent` is true.
  @ViewBuilder
  func marineBadge(isPresent: Bool) -> some View {
    if isPresent {
      self.overlay(alignment: .topTrailing) {
        Circle()
          .fill(Color.red)
          .frame(width: 16, height: 16)
          .alignmentGuide(.top) { $0[.top] }
          .alignmentGuide(.trailing) { $0[.trailing]}
      }
    } else {
      self
    }
  }
}
