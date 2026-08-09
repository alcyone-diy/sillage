//
//  MarineTelemetryHUDCard.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// An immutable item representing a single telemetry cell (e.g. SOG, COG, BTW, DISTANCE, BEARING).
public struct MarineTelemetryItem: Identifiable, Sendable {
  public let id: String
  public let label: LocalizedStringResource
  public let value: String
  public let isPlaceholder: Bool

  public init(id: String? = nil, label: LocalizedStringResource, value: String, isPlaceholder: Bool = false) {
    self.label = label
    self.id = id ?? "\(label.key)"
    self.value = value
    self.isPlaceholder = isPlaceholder
  }
}

/// Technical Design Choice: Deterministic HUD Layout Config
/// Speculative layout containers such as `ViewThatFits` are strictly prohibited in high-frequency marine HUD cards.
/// Speculative measurement loops trigger CPU/battery thrashing when rendered over a 60-120Hz MapLibre viewport.
/// `TelemetryHUDLayout` provides explicit, zero-measurement-overhead layout switching between horizontal strips and column grids.
public enum TelemetryHUDLayout: Sendable, Equatable, Hashable {
  case horizontal
  case grid(columns: Int)
}

/// A unified, highly performant marine telemetry HUD card.
/// Renders telemetry cells either in a continuous horizontal strip with vertical dividers
/// or in an explicit column-based grid without vertical dividers.
public struct MarineTelemetryHUDCard: View {
  let items: [MarineTelemetryItem]
  let layout: TelemetryHUDLayout
  @Environment(\.marineTheme) private var marineTheme

  public init(items: [MarineTelemetryItem], layout: TelemetryHUDLayout = .horizontal) {
    self.items = items
    self.layout = layout
  }

  public var body: some View {
    contentView
      .padding(.horizontal, MarineTheme.Spacing.medium)
      .padding(.vertical, MarineTheme.Spacing.small + 2)
      .background(
        .regularMaterial,
        in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
          .stroke(marineTheme.colors.border.opacity(0.4), lineWidth: MarineTheme.Metrics.borderWidth / 2)
      )
      .shadow(color: Color.black.opacity(0.15), radius: MarineTheme.Metrics.shadowRadius * 3, x: 0, y: MarineTheme.Metrics.shadowOffset * 3)
  }

  @ViewBuilder
  private var contentView: some View {
    switch layout {
    case .horizontal:
      HStack(spacing: MarineTheme.Spacing.medium) {
        ForEach(items) { item in
          if item.id != items.first?.id {
            Divider()
              .frame(height: MarineTheme.Metrics.hudDividerHeight)
          }

          cellView(for: item)
        }
      }
    case .grid(let columns):
      // Technical Design Choice: Safe Column Allocation & Spacing
      // Uses max(1, columns) to guarantee non-zero column counts and prevent runtime grid crashes.
      // Horizontal cell separation is managed via MarineTheme.Spacing.medium, and vertical row spacing via MarineTheme.Spacing.small.
      // Vertical dividers are intentionally omitted in grid mode to avoid visual clutter across grid rows.
      let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: MarineTheme.Spacing.medium),
        count: max(1, columns)
      )

      LazyVGrid(columns: gridColumns, spacing: MarineTheme.Spacing.small) {
        ForEach(items) { item in
          cellView(for: item)
            .frame(maxWidth: .infinity)
        }
      }
    }
  }

  @ViewBuilder
  private func cellView(for item: MarineTelemetryItem) -> some View {
    VStack(spacing: 2) {
      Text(item.label)
        .marineFont(.instrumentLabel)
        .foregroundColor(marineTheme.colors.textSecondary)

      Text(verbatim: item.value)
        .marineFont(.instrumentData)
        .foregroundColor(item.isPlaceholder ? marineTheme.colors.textSecondary : marineTheme.colors.textPrimary)
    }
  }
}

#Preview {
  let sampleItems = [
    MarineTelemetryItem(label: "SOG", value: "6.4 kn"),
    MarineTelemetryItem(label: "COG", value: "215°"),
    MarineTelemetryItem(label: "BTW", value: "210°"),
    MarineTelemetryItem(label: "DTW", value: "1.2 NM")
  ]

  VStack(spacing: MarineTheme.Spacing.large) {
    VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny) {
      Text("Horizontal Layout")
        .font(.caption)
        .foregroundStyle(.secondary)
      MarineTelemetryHUDCard(items: sampleItems, layout: .horizontal)
    }

    VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny) {
      Text("Grid Layout (2 columns)")
        .font(.caption)
        .foregroundStyle(.secondary)
      MarineTelemetryHUDCard(items: sampleItems, layout: .grid(columns: 2))
    }
  }
  .padding(MarineTheme.Spacing.medium)
  .background(Color.gray.opacity(0.2))
}
