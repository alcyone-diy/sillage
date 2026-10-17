//
//  MarinePositionPickerHUD.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation

/// Shared HUD providing real-time crosshair aiming, line-of-sight telemetry,
/// and a bottom action confirmation card for manual coordinate adjustment (e.g. anchor relocation, waypoint position).
public struct MarinePositionPickerHUD: View {
  let title: LocalizedStringKey
  let onCancel: @MainActor () -> Void
  let onConfirm: @MainActor (CLLocationCoordinate2D) -> Void

  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel: PanelManagerViewModel?
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.physicalSafeArea) private var physicalSafeArea

  public init(
    title: LocalizedStringKey,
    onCancel: @MainActor @escaping () -> Void,
    onConfirm: @MainActor @escaping (CLLocationCoordinate2D) -> Void
  ) {
    self.title = title
    self.onCancel = onCancel
    self.onConfirm = onConfirm
  }

  public var body: some View {
    ZStack {
      // 1. Central Crosshair (Fixed at center of map viewport)
      MarineCrosshairView.targetAiming(theme: marineTheme)

      VStack {
        // 2. Top Sightline Telemetry HUD (Isolated sub-view for 120fps rendering)
        LineOfSightSubView(chartViewModel: chartViewModel)
          .padding(.top, physicalSafeArea.top + MarineTheme.Spacing.hudCardTopPadding)

        Spacer()

        // 3. Bottom Action Controls & Instruction Prompt
        MarineActionConfirmationCard(
          title: title,
          onCancel: onCancel,
          onConfirm: {
            onConfirm(chartViewModel.centerCoordinate)
          },
          onHeightChange: { height in
            panelManagerViewModel?.actionConfirmationCardHeight = height
            panelManagerViewModel?.actionConfirmationCardBottomPadding = MarineTheme.Spacing.overlayCardBottom
          }
        )
        .padding(.horizontal, MarineTheme.Spacing.medium)
        .padding(.bottom, MarineTheme.Spacing.overlayCardBottom)
      }
    }
    // CRITICAL: Must ignore all safe areas so that this ZStack's mathematical center
    // perfectly aligns with the MapLibreView beneath it.
    .ignoresSafeArea()
  }
}

fileprivate struct LineOfSightSubView: View {
  let chartViewModel: ChartViewModel

  var body: some View {
    MarineLineOfSightHUDView(
      vesselCoordinate: chartViewModel.currentCoordinate,
      targetCoordinate: chartViewModel.centerCoordinate
    )
  }
}
