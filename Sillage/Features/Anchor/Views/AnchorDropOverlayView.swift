//
//  AnchorDropOverlayView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import OSLog

/// Technical Design Choice: Full-Screen Drop Anchor Preparation Overlay
/// Displays a `MarineActionConfirmationCard` at the bottom of the map viewport,
/// allowing the user to view the full chart while the anchor symbol dynamically tracks the vessel.
public struct AnchorDropOverlayView: View {
  @Environment(AnchorViewModel.self) private var anchorViewModel
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel: PanelManagerViewModel?
  @Environment(\.marineTheme) private var marineTheme

  public init() {}

  public var body: some View {
    VStack {
      Spacer()

      MarineActionConfirmationCard(
        title: "Confirm Anchor Drop",
        cancelTitle: "Cancel",
        cancelIcon: "xmark",
        onCancel: {
          Logger.anchor.info("User canceled drop anchor preparation mode")
          anchorViewModel.cancelPreparingDropAnchor()
          panelManagerViewModel?.openAnchorAlarmPanel()
        },
        confirmTitle: "Drop Anchor",
        confirmIcon: "water.waves.and.arrow.down",
        confirmStyle: marineTheme.colors.primary,
        onConfirm: {
          Logger.anchor.info("User confirmed drop anchor from full-screen overlay")
          anchorViewModel.confirmDropAnchor()
          panelManagerViewModel?.openAnchorAlarmPanel()
        }
      )
      .padding(.horizontal, MarineTheme.Spacing.medium)
      .padding(.bottom, 40)
    }
    .ignoresSafeArea()
  }
}
