//
//  MarineCloseButton.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-12.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Standard marine close button respecting Glove Mode scaling,
/// Fitts's Law touch target boundaries, and high-glare marine contrast tokens.
@MainActor
struct MarineCloseButton: View {
  @Environment(\.marineTheme) private var marineTheme

  let action: @MainActor () -> Void

  var body: some View {
    Button(action: action) {
      Image(marineIcon: .close)
        .marineFont(.caption)
        .bold()
        .foregroundStyle(marineTheme.colors.textSecondary)
        .frame(
          width: marineTheme.metrics.closeButtonCircleSize,
          height: marineTheme.metrics.closeButtonCircleSize
        )
        .background(marineTheme.colors.surfaceBackground, in: Circle())
    }
    .buttonStyle(.plain)
    .frame(minWidth: marineTheme.minTouchTarget, minHeight: marineTheme.minTouchTarget)
    .contentShape(Rectangle())
    .accessibilityLabel(Text("Close"))
  }
}
