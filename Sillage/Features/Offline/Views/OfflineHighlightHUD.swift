//
//  OfflineHighlightHUD.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Floating marine HUD capsule displaying the currently highlighted offline chart area on the map.
/// Conforms to Fitts's Law and Glove Mode standards with generous touch targets.
struct OfflineHighlightHUD: View {
  let region: HighlightedOfflineRegion
  var onRecenter: (() -> Void)? = nil
  let onDismiss: () -> Void

  var body: some View {
    OfflineRegionBadgeView(
      name: region.name,
      onRecenter: onRecenter,
      onDismiss: onDismiss
    )
  }
}
