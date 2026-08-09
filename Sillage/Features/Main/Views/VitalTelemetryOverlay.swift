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

/// An adaptive overlay displaying vital navigation telemetry metrics (SOG, COG, and optional BTW).
/// Automatically switches between a 2-column grid layout in Compact size classes (iPhone Portrait)
/// and a continuous horizontal strip in Regular size classes (iPhone Landscape, iPad).
@MainActor
public struct VitalTelemetryOverlay: View {
  @Environment(ChartViewModel.self) private var chartViewModel: ChartViewModel?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  public init() {}

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
    MarineTelemetryHUDCard(items: telemetryItems, layout: currentLayout)
  }

  /// Maps current `ChartViewModel` telemetry state into domain `MarineTelemetryItem` structs.
  /// Strictly enforces "No Data" rules ("---" for speed, "---°" for bearings) and conditionally appends
  /// Bearing To Waypoint (BTW) only when an active route or target waypoint is active.
  private var telemetryItems: [MarineTelemetryItem] {
    let sog = chartViewModel?.smoothedSOG
    let cog = chartViewModel?.smoothedCOG
    let btw = chartViewModel?.bearingToWaypoint

    let sogString = sog?.marineFormatted ?? "---"
    let cogString = cog?.marineBearingFormatted ?? "---°"
    let btwString = btw?.marineBearingFormatted ?? "---°"

    var items = [
      MarineTelemetryItem(label: "SOG", value: sogString, isPlaceholder: sog == nil),
      MarineTelemetryItem(label: "COG", value: cogString, isPlaceholder: cog == nil)
    ]

    if chartViewModel?.goToWaypointVisualState != nil {
      items.append(
        MarineTelemetryItem(label: "BTW", value: btwString, isPlaceholder: btw == nil)
      )
    }

    return items
  }
}

#Preview("Vital Telemetry Overlay") {
  VStack(spacing: 24) {
    VStack(alignment: .leading, spacing: 6) {
      Text("Compact / Portrait Mode (.grid)")
        .font(.caption)
        .foregroundStyle(.secondary)
      VitalTelemetryOverlay()
        .environment(\.horizontalSizeClass, .compact)
    }

    VStack(alignment: .leading, spacing: 6) {
      Text("Regular / Landscape Mode (.horizontal)")
        .font(.caption)
        .foregroundStyle(.secondary)
      VitalTelemetryOverlay()
        .environment(\.horizontalSizeClass, .regular)
    }
  }
  .padding()
  .background(Color.gray.opacity(0.3))
}
