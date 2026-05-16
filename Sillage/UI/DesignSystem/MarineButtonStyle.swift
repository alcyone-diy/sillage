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
  @ScaledMetric(relativeTo: .body) private var scaleFactor: CGFloat = 1.0

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(
        minWidth: marineTheme.minTouchTarget * scaleFactor,
        minHeight: marineTheme.minTouchTarget * scaleFactor
      )
      .opacity(configuration.isPressed ? 0.5 : 1.0)
      .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
      .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
  }
}
