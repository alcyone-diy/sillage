//
//  MarineDetailRow.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// A standardized detail row component for displaying key-value pairs across detail views.
/// Adheres to MarineTheme design guidelines and uses a left-aligned vertical layout for readability.
struct MarineDetailRow: View {
  @Environment(\.marineTheme) private var marineTheme

  let label: LocalizedStringKey
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny) {
      Text(label)
        .marineFont(.caption)
        .foregroundStyle(marineTheme.colors.textSecondary)
      Text(verbatim: value)
        .marineFont(.body)
        .foregroundStyle(marineTheme.colors.textPrimary)
        .textSelection(.enabled)
    }
  }
}
