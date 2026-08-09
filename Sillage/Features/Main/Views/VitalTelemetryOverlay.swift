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

/// An adaptive overlay displaying vital navigation telemetry metrics (SOG, COG, and optional BTW, RNG, XTE).
/// Automatically switches between a 2-column grid layout in Compact size classes (iPhone Portrait)
/// and a continuous horizontal strip in Regular size classes (iPhone Landscape, iPad).
@MainActor
public struct VitalTelemetryOverlay: View {
  @Environment(ChartViewModel.self) private var chartViewModel: ChartViewModel?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.locale) private var locale

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
  /// Strictly enforces "No Data" rules ("---" for speed and distance metrics, "---°" for bearing metrics)
  /// and conditionally appends Route Navigation metrics (BTW, RNG, XTE) when an active route or waypoint is set.
  private var telemetryItems: [MarineTelemetryItem] {
    let sog = chartViewModel?.smoothedSOG
    let cog = chartViewModel?.smoothedCOG

    let sogString = sog?.marineFormatted ?? "---"
    let cogString = cog?.marineBearingFormatted ?? "---°"

    var items = [
      MarineTelemetryItem(label: "SOG", value: sogString, isPlaceholder: sog == nil),
      MarineTelemetryItem(label: "COG", value: cogString, isPlaceholder: cog == nil)
    ]

    if chartViewModel?.goToWaypointVisualState != nil {
      let btw = chartViewModel?.bearingToWaypoint
      let rng = chartViewModel?.rangeToWaypoint
      let xte = chartViewModel?.crossTrackError

      let btwString = btw?.marineBearingFormatted ?? "---°"
      let rngString = rng?.marineContextualDistanceFormatted(locale: locale) ?? "---"
      let xteString = xte?.marineCrossTrackFormatted ?? "---"

      items.append(MarineTelemetryItem(label: "BTW", value: btwString, isPlaceholder: btw == nil))
      items.append(MarineTelemetryItem(label: "RNG", value: rngString, isPlaceholder: rng == nil))
      items.append(MarineTelemetryItem(label: "XTE", value: xteString, isPlaceholder: xte == nil))
    }

    return items
  }
}

#Preview("Vital Telemetry Overlay") {
  let sampleItemsInactive = [
    MarineTelemetryItem(label: "SOG", value: "6.4 kn"),
    MarineTelemetryItem(label: "COG", value: "215°")
  ]

  let sampleItemsActiveRoute = [
    MarineTelemetryItem(label: "SOG", value: "6.4 kn"),
    MarineTelemetryItem(label: "COG", value: "215°"),
    MarineTelemetryItem(label: "BTW", value: "210°"),
    MarineTelemetryItem(label: "RNG", value: "1.2 NM"),
    MarineTelemetryItem(label: "XTE", value: "0.02 NM")
  ]

  VStack(spacing: 24) {
    VStack(alignment: .leading, spacing: 6) {
      Text("Compact / Portrait Mode - Standby (.grid)")
        .font(.caption)
        .foregroundStyle(.secondary)
      MarineTelemetryHUDCard(items: sampleItemsInactive, layout: .grid(columns: 2))
    }

    VStack(alignment: .leading, spacing: 6) {
      Text("Compact / Portrait Mode - Active Route (.grid 5 items)")
        .font(.caption)
        .foregroundStyle(.secondary)
      MarineTelemetryHUDCard(items: sampleItemsActiveRoute, layout: .grid(columns: 2))
    }

    VStack(alignment: .leading, spacing: 6) {
      Text("Regular / Landscape Mode - Active Route (.horizontal 5 items)")
        .font(.caption)
        .foregroundStyle(.secondary)
      MarineTelemetryHUDCard(items: sampleItemsActiveRoute, layout: .horizontal)
    }
  }
  .padding()
  .background(Color.gray.opacity(0.3))
}
