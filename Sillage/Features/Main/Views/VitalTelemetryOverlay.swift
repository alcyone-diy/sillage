//
//  VitalTelemetryOverlay.swift
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
/// Supports interactive Edit Mode (`isEditingHUD == true`), triggered via a 0.8s long press gesture.
@MainActor
public struct VitalTelemetryOverlay: View {
  @Environment(ChartViewModel.self) private var chartViewModel: ChartViewModel?
  @Environment(TelemetryPreferences.self) private var envPreferences: TelemetryPreferences?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.locale) private var locale

  @State private var secondaryViewModel = SecondaryTelemetryViewModel()
  @State private var isEditingHUD: Bool = false
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
      return .grid(columns: 2)
    } else {
      return .horizontal
    }
  }

  public var body: some View {
    ZStack {
      if isEditingHUD {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture {
            isEditingHUD = false
          }
      }

      MarineTelemetryHUDCard(
        items: telemetryItems,
        layout: currentLayout,
        isEditing: isEditingHUD,
        onItemTapped: { metricId in
          guard isEditingHUD else { return }
          if let metric = TelemetryMetric(rawValue: metricId) {
            preferences.activeMetrics.removeAll(where: { $0 == metric })
          }
        }
      )
      .onLongPressGesture(minimumDuration: 0.8) {
        if !isEditingHUD {
          isEditingHUD = true
        }
      }
    }
  }

  /// Maps user-configured `TelemetryMetric` cases from `TelemetryPreferences` into `MarineTelemetryItem` structs.
  /// Dynamically extracts data from `ChartViewModel` and `SecondaryTelemetryViewModel` and strictly enforces
  /// "No Data" formatting ("---" for speed/distance/battery metrics, "---°" for bearings) when values are missing.
  private var telemetryItems: [MarineTelemetryItem] {
    preferences.activeMetrics.map { (metric: TelemetryMetric) -> MarineTelemetryItem in
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
        let batteryItem = secondaryViewModel.items.first(where: { $0.id == "BATTERY" })
        let string = batteryItem?.value ?? "---"
        let isPlaceholder = batteryItem?.isPlaceholder ?? true
        return MarineTelemetryItem(id: metric.id, label: metric.label, value: string, isPlaceholder: isPlaceholder)
      }
    }
  }
}

#Preview("Vital Telemetry Overlay") {
  struct PreviewContainer: View {
    let defaultPrefs: TelemetryPreferences = TelemetryPreferences()
    let fullPrefs: TelemetryPreferences = {
      let prefs = TelemetryPreferences()
      prefs.activeMetrics = TelemetryMetric.allCases
      return prefs
    }()

    var body: some View {
      VStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Compact / Portrait Mode - Default Metrics (.grid)")
            .font(.caption)
            .foregroundStyle(.secondary)
          VitalTelemetryOverlay(preferences: defaultPrefs)
            .environment(\.horizontalSizeClass, .compact)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Compact / Portrait Mode - All Metrics (.grid 6 items)")
            .font(.caption)
            .foregroundStyle(.secondary)
          VitalTelemetryOverlay(preferences: fullPrefs)
            .environment(\.horizontalSizeClass, .compact)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Regular / Landscape Mode - All Metrics (.horizontal)")
            .font(.caption)
            .foregroundStyle(.secondary)
          VitalTelemetryOverlay(preferences: fullPrefs)
            .environment(\.horizontalSizeClass, .regular)
        }
      }
      .padding()
      .background(Color.gray.opacity(0.3))
    }
  }

  return PreviewContainer()
}
