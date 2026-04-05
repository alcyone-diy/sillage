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

  static let standard = MarineTheme(minTouchTarget: 44, isGloveMode: false)
  static let gloveMode = MarineTheme(minTouchTarget: 66, isGloveMode: true)
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
