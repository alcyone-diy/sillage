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

/// A unified, highly performant marine telemetry HUD card.
/// Renders a horizontal strip of telemetry cells separated by vertical dividers.
public struct MarineTelemetryHUDCard: View {
  let items: [MarineTelemetryItem]
  @Environment(\.marineTheme) private var marineTheme

  public init(items: [MarineTelemetryItem]) {
    self.items = items
  }

  public var body: some View {
    HStack(spacing: MarineTheme.Spacing.medium) {
      ForEach(items) { item in
        if item.id != items.first?.id {
          Divider()
            .frame(height: MarineTheme.Metrics.hudDividerHeight)
        }

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
}
