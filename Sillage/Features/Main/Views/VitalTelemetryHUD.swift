//
//  VitalTelemetryHUD.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// An adaptive, user-customizable overlay displaying vital navigation and hardware telemetry metrics.
/// Dynamically renders user-selected metrics from `TelemetryPreferences` (e.g. SOG, COG, BTW, RNG, XTE, Battery)
/// and automatically switches between a 2-column grid layout in Compact size classes (iPhone Portrait)
/// and a continuous horizontal strip in Regular size classes (iPhone Landscape, iPad).
/// Supports interactive Edit Mode (`isEditingHUD == true`), squish long-press feedback, and ephemeral short-tap hint toasts capped at 2 successful Edit Mode entries.
@MainActor
public struct VitalTelemetryHUD: View {
  @Environment(ChartViewModel.self) private var chartViewModel: ChartViewModel?
  @Environment(TelemetryPreferences.self) private var envPreferences: TelemetryPreferences?
  @Environment(PreferencesService.self) private var preferencesService: PreferencesService?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.locale) private var locale
  @Environment(\.marineTheme) private var marineTheme

  @Environment(SecondaryTelemetryViewModel.self) private var secondaryViewModel: SecondaryTelemetryViewModel?
  @State private var isEditingHUD: Bool = false
  @State private var isPressingHUD: Bool = false
  @State private var showEditHint: Bool = false
  @State private var hintTask: Task<Void, Never>? = nil

  private var customPreferences: TelemetryPreferences?

  public init(preferences: TelemetryPreferences? = nil) {
    self.customPreferences = preferences
  }

  private var preferences: TelemetryPreferences {
    customPreferences ?? envPreferences ?? TelemetryPreferences()
  }

  /// Technical Design Choice: Speculative-Free Layout Adaptation
  /// Replaces multi-pass `ViewThatFits` measuring wrappers with explicit environment size class checks.
  /// Compact horizontal size classes (e.g. iPhone portrait) use a 2-column grid layout,
  /// while regular size classes (e.g. iPhone landscape, iPad) use a single horizontal strip.
  private var currentLayout: TelemetryHUDLayout {
    if horizontalSizeClass == .compact {
      return .grid(columns: 4)
    } else {
      return .horizontal
    }
  }

  public var body: some View {
    VStack(spacing: MarineTheme.Spacing.medium) {
      MarineTelemetryHUDCard(
        items: telemetryItems,
        layout: currentLayout,
        editMode: isEditingHUD ? .remove : .none,
        onItemTapped: { metricId in
          guard isEditingHUD else { return }
          if let metric = TelemetryMetric(rawValue: metricId) {
            withAnimation(.default) {
              preferences.activeMetrics.removeAll(where: { $0 == metric })
            }
          }
        }
      )
      .scaleEffect((isPressingHUD && !isEditingHUD) ? 0.95 : 1.0)
      .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressingHUD)
      .onLongPressGesture(minimumDuration: 0.8) { isPressing in
        guard !isEditingHUD else {
          isPressingHUD = false
          return
        }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
          isPressingHUD = isPressing
        }
      } perform: {
        guard !isEditingHUD else { return }
        isPressingHUD = false
        withAnimation(.spring()) {
          isEditingHUD = true
          showEditHint = false
          preferencesService?.hudEditOpenCount = (preferencesService?.hudEditOpenCount ?? 0) + 1
        }
      }
      .simultaneousGesture(
        TapGesture().onEnded {
          let openCount = preferencesService?.hudEditOpenCount ?? 0
          guard !isEditingHUD, openCount < 2 else { return }

          hintTask?.cancel()
          withAnimation(.easeInOut(duration: 0.25)) {
            showEditHint = true
          }
          hintTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
              showEditHint = false
            }
          }
        }
      )

      if showEditHint && !isEditingHUD {
        HStack(spacing: 6) {
          Image(systemName: "hand.tap.fill")
            .font(.system(size: 12))
            .foregroundColor(marineTheme.colors.accent)

          Text("Long press to customize")
            .marineFont(.caption)
            .foregroundColor(marineTheme.colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
          .ultraThinMaterial,
          in: Capsule()
        )
        .overlay(
          Capsule()
            .stroke(marineTheme.colors.border.opacity(0.3), lineWidth: MarineTheme.Metrics.borderWidth / 2)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
      }

      if isEditingHUD {
        reservoirOverlay
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .onChange(of: isEditingHUD) { _, _ in
      isPressingHUD = false
    }
    .animation(.spring(), value: isEditingHUD)
    .animation(.default, value: preferences.activeMetrics)
  }

  /// Telemetry Reservoir overlay presenting inactive instruments available for addition to the main HUD card.
  @ViewBuilder
  private var reservoirOverlay: some View {
    VStack(spacing: MarineTheme.Spacing.small) {
      HStack {
        Text("Available Instruments")
          .marineFont(.subheadline)
          .foregroundColor(marineTheme.colors.textSecondary)

        Spacer()

        Button {
          isPressingHUD = false
          withAnimation(.spring()) {
            isEditingHUD = false
          }
        } label: {
          Text("Done")
            .marineFont(.subheadline)
            .padding(.horizontal, MarineTheme.Spacing.medium)
            .padding(.vertical, 6)
            .background(marineTheme.colors.accent, in: Capsule())
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
      }

      if inactiveTelemetryItems.isEmpty {
        Text("All instruments are active in HUD")
          .marineFont(.subheadline)
          .foregroundColor(marineTheme.colors.textSecondary)
          .padding(.vertical, MarineTheme.Spacing.small)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          MarineTelemetryHUDCard(
            items: inactiveTelemetryItems,
            layout: .horizontal,
            editMode: .add,
            onItemTapped: { metricId in
              if let metric = TelemetryMetric(rawValue: metricId) {
                withAnimation(.default) {
                  preferences.activeMetrics.append(metric)
                }
              }
            }
          )
        }
      }
    }
    .padding(MarineTheme.Spacing.medium)
    .background(
      .ultraThinMaterial,
      in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
        .stroke(marineTheme.colors.border.opacity(0.3), lineWidth: MarineTheme.Metrics.borderWidth / 2)
    )
    .shadow(color: Color.black.opacity(0.2), radius: MarineTheme.Metrics.shadowRadius * 2, x: 0, y: MarineTheme.Metrics.shadowOffset)
  }

  private var telemetryItems: [MarineTelemetryItem] {
    preferences.activeMetrics.map { createTelemetryItem(for: $0) }
  }

  private var inactiveTelemetryItems: [MarineTelemetryItem] {
    let inactiveMetrics = TelemetryMetric.allCases.filter { !preferences.activeMetrics.contains($0) }
    return inactiveMetrics.map { createTelemetryItem(for: $0) }
  }

  /// Utility function (DRY) encapsulating individual metric extraction and formatting logic.
  /// Strictly enforces "No Data" formatting ("---" for speed/distance/battery metrics, "---°" for bearings) when values are missing.
  private func createTelemetryItem(for metric: TelemetryMetric) -> MarineTelemetryItem {
    switch metric {
    case .sog:
      let value = chartViewModel?.smoothedSOG
      let string = value?.marineFormatted ?? "---"
      return MarineTelemetryItem(id: metric.id, label: metric.label, value: string, isPlaceholder: value == nil)

    case .cog:
      let value = chartViewModel?.smoothedCOG
      let string = value?.marineBearingFormatted ?? "---°"
      return MarineTelemetryItem(id: metric.id, label: metric.label, value: string, isPlaceholder: value == nil)

    case .btw:
      let value = chartViewModel?.bearingToWaypoint
      let string = value?.marineBearingFormatted ?? "---°"
      return MarineTelemetryItem(id: metric.id, label: metric.label, value: string, isPlaceholder: value == nil)

    case .rng:
      let value = chartViewModel?.rangeToWaypoint
      let string = value?.marineContextualDistanceFormatted(locale: locale) ?? "---"
      return MarineTelemetryItem(id: metric.id, label: metric.label, value: string, isPlaceholder: value == nil)

    case .xte:
      let value = chartViewModel?.crossTrackError
      let string = value?.marineCrossTrackFormatted ?? "---"
      return MarineTelemetryItem(id: metric.id, label: metric.label, value: string, isPlaceholder: value == nil)

    case .battery:
      let batteryItem = secondaryViewModel?.items.first(where: { $0.id == "BATTERY" })
      let string = batteryItem?.value ?? "---"
      let isPlaceholder = batteryItem?.isPlaceholder ?? true
      return MarineTelemetryItem(id: metric.id, label: metric.label, value: string, isPlaceholder: isPlaceholder)
    }
  }
}

#Preview("Vital Telemetry HUD") {
  struct PreviewContainer: View {
    let defaultPrefs: TelemetryPreferences = TelemetryPreferences()
    let partialPrefs: TelemetryPreferences = {
      let prefs = TelemetryPreferences()
      prefs.activeMetrics = [.sog, .cog]
      return prefs
    }()

    var body: some View {
      VStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Compact Mode - Default Active Metrics")
            .font(.caption)
            .foregroundStyle(.secondary)
          VitalTelemetryHUD(preferences: defaultPrefs)
            .environment(\.horizontalSizeClass, .compact)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Compact Mode - Partial Active Metrics (SOG & COG)")
            .font(.caption)
            .foregroundStyle(.secondary)
          VitalTelemetryHUD(preferences: partialPrefs)
            .environment(\.horizontalSizeClass, .compact)
        }
      }
      .padding()
      .background(Color.gray.opacity(0.3))
    }
  }

  return PreviewContainer()
}
