//
//  MarineButtonStyle.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct MarineButtonStyle: ButtonStyle {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.isEnabled) private var isEnabled
  @ScaledMetric(relativeTo: .body) private var scaleFactor: CGFloat = 1.0

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(minHeight: marineTheme.minTouchTarget * scaleFactor)
      .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
      .opacity(configuration.isPressed ? 0.5 : 1.0)
      .opacity(isEnabled ? 1.0 : 0.5)
      .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
  }
}

extension ButtonStyle where Self == MarineButtonStyle {
  static var marine: MarineButtonStyle {
    MarineButtonStyle()
  }
}
