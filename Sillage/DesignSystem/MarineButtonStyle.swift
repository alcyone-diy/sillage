//
//  MarineButtonStyle.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct MarineButtonStyle: ButtonStyle {
  enum Variant {
    case custom
    case primary
    case secondary
    case destructive
    case cancel
  }

  var variant: Variant = .custom
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.marineTheme) private var marineTheme
  @ScaledMetric(relativeTo: .body) private var scaleFactor: CGFloat = 1.0

  init(_ variant: Variant = .custom) {
    self.variant = variant
  }

  func makeBody(configuration: Configuration) -> some View {
    let targetMinHeight = marineTheme.minTouchTarget * scaleFactor

    configuration.label
      .font(variant == .custom ? nil : .headline)
      .fontWeight(variant == .custom ? nil : .semibold)
      .foregroundStyle(foregroundColor(for: variant))
      .frame(
        minWidth: variant == .custom ? marineTheme.minTouchTarget * scaleFactor : nil,
        maxWidth: variant == .custom ? nil : .infinity,
        minHeight: targetMinHeight
      )
      .background(
        backgroundColor(for: variant),
        in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
      )
      .opacity(configuration.isPressed ? MarineTheme.Metrics.pressedOpacity : 1.0)
      .scaleEffect(configuration.isPressed ? MarineTheme.Metrics.pressedScale : 1.0)
      .animation(.easeInOut(duration: MarineTheme.Metrics.animationDuration), value: configuration.isPressed)
  }

  // MARK: - Private Helpers

  private func backgroundColor(for variant: Variant) -> Color {
    guard isEnabled else { return variant == .custom ? .clear : marineTheme.colors.disabledBackground }
    switch variant {
    case .custom:
      return .clear
    case .primary:
      return marineTheme.colors.primary
    case .secondary:
      return marineTheme.colors.secondaryActionBackground
    case .destructive:
      return marineTheme.colors.destructive
    case .cancel:
      return marineTheme.colors.cancelAction
    }
  }

  private func foregroundColor(for variant: Variant) -> Color {
    guard isEnabled else { return marineTheme.colors.inactive }
    switch variant {
    case .custom:
      return .primary
    case .primary, .destructive, .cancel:
      return marineTheme.colors.onPrimary
    case .secondary:
      return marineTheme.colors.primary
    }
  }
}
