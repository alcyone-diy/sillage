//
//  MarineToggleButton.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct MarineToggleButton: View {
  let title: LocalizedStringKey
  let icon: MarineIcon
  @Binding var isOn: Bool

  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    VStack(spacing: MarineTheme.Spacing.small) {
      Image(marineIcon: icon)
        .font(.title2)
      Text(title)
        .marineFont(.caption)
    }
    .frame(maxWidth: .infinity, minHeight: marineTheme.metrics.touchTarget)
    .foregroundColor(isOn ? MarineTheme.Colors.textOnActive : MarineTheme.Colors.textSecondary)
    .background(isOn ? MarineTheme.Colors.activeToggle : MarineTheme.Colors.secondarySurface)
    .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius))
    .contentShape(Rectangle())
    .scaleEffect(isOn ? 1.02 : 1.0)
    .onTapGesture {
      let impact = UIImpactFeedbackGenerator(style: .medium)
      impact.impactOccurred()
      withAnimation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)) {
        isOn.toggle()
      }
    }
  }
}

#Preview {
  struct PreviewWrapper: View {
    @State private var isOn = false
    var body: some View {
      HStack {
        MarineToggleButton(title: "Glove Mode", icon: .gloveMode, isOn: $isOn)
        MarineToggleButton(title: "Track", icon: .record, isOn: .constant(false))
      }
      .padding()
      .environment(\.marineTheme, .standard)
    }
  }
  return PreviewWrapper()
}
