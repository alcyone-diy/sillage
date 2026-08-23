//
//  TrackExportProgressDialog.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Technical Design Choice: Floating Marine Track Export Progress Dialog
///
/// 1. **Non-Blocking Marine Viewport:**
///    In offshore sailing, critical cartographic and telemetry awareness must never be entirely obstructed.
///    This dialog uses a floating card layout with a lightweight, non-opaque backdrop so instruments
///    and vessel positioning remain partially visible during the export.
///
/// 2. **Marine UX & Glove Mode:**
///    The "Cancel" action is styled with `MarineButtonStyle` to strictly enforce `marineTheme.minTouchTarget`
///    (66pt in Glove Mode), allowing reliable one-tap cancellation even with wet hands or heavy vessel motion.
public struct TrackExportProgressDialog: View {
  let progress: Double
  let onCancel: @MainActor () -> Void

  @Environment(\.marineTheme) private var marineTheme

  public init(
    progress: Double,
    onCancel: @MainActor @escaping () -> Void
  ) {
    self.progress = progress
    self.onCancel = onCancel
  }

  public var body: some View {
    ZStack {
      // Invisible full-screen touch and gesture barrier that strictly absorbs all interaction
      Color.clear
        .contentShape(Rectangle())
        .ignoresSafeArea()
        // Absorbs taps
        .onTapGesture {}
        // Absorbs scrolls and map pan/drag gestures
        .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { _ in })

      VStack(spacing: MarineTheme.Spacing.medium) {
        // Header
        HStack(spacing: MarineTheme.Spacing.small) {
          Image(marineIcon: .track)
            .foregroundStyle(marineTheme.colors.primary)
            .font(.title3)

          Text("Exporting Track…")
            .marineFont(.headline)
            .foregroundStyle(marineTheme.colors.textPrimary)

          Spacer()
        }

        // Progress indicator
        VStack(spacing: MarineTheme.Spacing.tiny) {
          ProgressView(value: progress, total: 1.0)
            .progressViewStyle(.linear)
            .tint(marineTheme.colors.primary)

          HStack {
            Text("Preparing GPX file…")
              .marineFont(.caption)
              .foregroundStyle(marineTheme.colors.textSecondary)

            Spacer()

            Text("\(Int(progress * 100))%")
              .marineFont(.subheadline)
              .monospacedDigit()
              .fontWeight(.semibold)
              .foregroundStyle(marineTheme.colors.textPrimary)
          }
        }
        .padding(.vertical, MarineTheme.Spacing.small)

        // Cancel action
        Button(action: onCancel) {
          HStack(spacing: MarineTheme.Spacing.small) {
            Image(marineIcon: .close)
            Text("Cancel")
          }
        }
        .buttonStyle(MarineButtonStyle(.cancel))
        .accessibilityLabel(String(localized: "Cancel Export"))
      }
      .padding(MarineTheme.Spacing.large)
      .frame(maxWidth: 340)
      .background(.thickMaterial)
      .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous))
      .shadow(color: Color.black.opacity(0.15), radius: 24, x: 0, y: 8)
      .padding(MarineTheme.Spacing.medium)
    }
  }
}
