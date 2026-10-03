//
//  ActiveChecklistButtonView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Floating action button that appears when at least one checklist is in progress.
/// Displays an inner circular progress ring indicating the proportion of completed steps
/// across all in-progress checklists.
@MainActor
struct ActiveChecklistButtonView: View {
  @Environment(\.marineTheme) private var marineTheme

  let progress: Double
  let action: () -> Void

  init(progress: Double = 0.0, action: @escaping () -> Void = {}) {
    self.progress = progress
    self.action = action
  }

  private var ringLineWidth: CGFloat {
    marineTheme.isGloveMode ? 3.0 : 2.0
  }

  private var ringOffset: CGFloat {
    marineTheme.isGloveMode ? 4.5 : 3.0
  }

  var body: some View {
    Button(action: action) {
      Image(marineIcon: .checklist)
        .marineFont(.title2)
        .foregroundColor(.white)
    }
    .buttonStyle(MarineFABStyle(backgroundColor: marineTheme.colors.caution))
    .overlay {
      ZStack {
        // Track ring (faded white against orange button)
        Circle()
          .stroke(Color.white.opacity(0.3), lineWidth: ringLineWidth)

        // Progress ring
        Circle()
          .trim(from: 0, to: CGFloat(min(max(progress, 0.0), 1.0)))
          .stroke(
            Color.white,
            style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
          .animation(.easeInOut(duration: 0.25), value: progress)
      }
      .padding(ringOffset)
    }
    .accessibilityLabel(String(localized: "Active Checklists"))
    .accessibilityValue("\(Int((min(max(progress, 0.0), 1.0) * 100).rounded()))%")
  }
}

#Preview {
  VStack(spacing: 20) {
    ActiveChecklistButtonView(progress: 0.25)
    ActiveChecklistButtonView(progress: 0.75)
  }
  .padding()
  .background(Color.gray)
}
