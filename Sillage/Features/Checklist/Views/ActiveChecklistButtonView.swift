//
//  ActiveChecklistButtonView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Floating action button that appears when at least one checklist is in progress.
@MainActor
struct ActiveChecklistButtonView: View {
  @Environment(\.marineTheme) private var marineTheme

  let action: () -> Void

  init(action: @escaping () -> Void = {}) {
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Image(marineIcon: .checklist)
        .marineFont(.title2)
        .foregroundColor(.white)
    }
    .buttonStyle(MarineFABStyle(backgroundColor: marineTheme.colors.primary))
    .accessibilityLabel(String(localized: "Active Checklists"))
  }
}

#Preview {
  ActiveChecklistButtonView()
}
