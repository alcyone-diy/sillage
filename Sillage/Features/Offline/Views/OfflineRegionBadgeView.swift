//
//  OfflineRegionBadgeView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Marine badge/HUD capsule displaying an offline chart region name and icon.
/// Supports both compact static labels (e.g. centroid markers during selection mode)
/// and interactive action HUDs (recenter and dismiss buttons conforming to Glove Mode).
struct OfflineRegionBadgeView: View {
  @Environment(\.marineTheme) private var marineTheme

  let name: String
  var onRecenter: (() -> Void)? = nil
  var onDismiss: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: MarineTheme.Spacing.small) {
      if let onRecenter {
        // Interactive re-center button (Fitts's law / Glove Mode)
        Button(action: onRecenter) {
          contentLabel(iconStyle: .body)
            .padding(.leading, MarineTheme.Spacing.medium)
            .padding(.vertical, MarineTheme.Spacing.small)
            .frame(minHeight: marineTheme.minTouchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Recenter on offline chart: \(name)"))
      } else {
        // Compact static label
        contentLabel(iconStyle: .caption)
          .padding(.horizontal, MarineTheme.Spacing.small + 4)
          .padding(.vertical, MarineTheme.Spacing.tiny + 2)
      }

      if let onDismiss {
        // Dismiss button (Cross)
        Button(action: onDismiss) {
          Image(marineIcon: .close)
            .marineFont(.body)
            .bold()
            .foregroundStyle(marineTheme.colors.textSecondary)
            .frame(minWidth: marineTheme.minTouchTarget, minHeight: marineTheme.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Hide offline chart frame"))
        .padding(.trailing, MarineTheme.Spacing.tiny)
      }
    }
    .background(.regularMaterial, in: Capsule())
    .overlay(
      Capsule()
        .strokeBorder(marineTheme.colors.accent.opacity(0.8), lineWidth: MarineTheme.Metrics.borderWidth * 1.5)
    )
    .shadow(
      color: Color.black.opacity(0.25),
      radius: MarineTheme.Metrics.shadowRadius,
      x: 0,
      y: MarineTheme.Metrics.shadowOffset
    )
  }

  @ViewBuilder
  private func contentLabel(iconStyle: MarineTextStyle) -> some View {
    HStack(spacing: MarineTheme.Spacing.tiny + 2) {
      Image(marineIcon: .offlineChart)
        .marineFont(iconStyle)
        .foregroundStyle(marineTheme.colors.accent)

      Text(name)
        .marineFont(.subheadline)
        .bold()
        .foregroundStyle(marineTheme.colors.textPrimary)
        .lineLimit(1)
    }
  }
}
