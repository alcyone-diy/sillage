//
//  MarineFABStyle.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct MarineFABStyle: ButtonStyle {
  let backgroundColor: Color
  @Environment(\.marineTheme) private var marineTheme
  @ScaledMetric(relativeTo: .body) private var scaleFactor: CGFloat = 1.0

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(
        width: marineTheme.minTouchTarget * scaleFactor,
        height: marineTheme.minTouchTarget * scaleFactor
      )
      .background(backgroundColor)
      .clipShape(Circle())
      .shadow(radius: 5)
      .opacity(configuration.isPressed ? 0.7 : 1.0)
      .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
      .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
  }
}
