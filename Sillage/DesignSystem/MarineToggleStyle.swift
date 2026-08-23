//
//  MarineToggleStyle.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct MarineToggleStyle: ToggleStyle {
  let icon: MarineIcon
  
  @Environment(\.marineTheme) private var marineTheme

  func makeBody(configuration: Configuration) -> some View {
    Button {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)) {
        configuration.isOn.toggle()
      }
    } label: {
      VStack(spacing: MarineTheme.Spacing.small) {
        Image(marineIcon: icon)
          .font(.title2)
        configuration.label
          .marineFont(.caption)
      }
      .frame(maxWidth: .infinity, minHeight: marineTheme.metrics.touchTarget)
      .foregroundColor(configuration.isOn ? marineTheme.colors.textOnActive : marineTheme.colors.textSecondary)
      .background {
        if configuration.isOn {
          marineTheme.colors.activeToggle
        } else {
          MarineCellBackgroundView()
        }
      }
    }
    .buttonStyle(MarineToggleButtonStyle())
    .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius))
    .contentShape(Rectangle())
    .scaleEffect(configuration.isOn ? 1.02 : 1.0)
    .sensoryFeedback(.impact(weight: .medium), trigger: configuration.isOn)
  }
}

private struct MarineToggleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .overlay(
        configuration.isPressed ? Color(uiColor: .systemFill) : Color.clear
      )
  }
}

extension ToggleStyle where Self == MarineToggleStyle {
  static func marine(icon: MarineIcon) -> MarineToggleStyle {
    MarineToggleStyle(icon: icon)
  }
}

#Preview {
  struct PreviewWrapper: View {
    @State private var isOn = false
    var body: some View {
      HStack {
        Toggle("Glove Mode", isOn: $isOn)
          .toggleStyle(.marine(icon: .gloveMode))
        Toggle("Track", isOn: .constant(false))
          .toggleStyle(.marine(icon: .record))
      }
      .padding()
      .environment(\.marineTheme, .standard)
    }
  }
  return PreviewWrapper()
}
