//
//  AnchorAdjustHUD.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation
import OSLog

/// Overlay view providing real-time crosshair aiming and sightline telemetry for manual anchor position adjustment.
public struct AnchorAdjustHUD: View {
  @Environment(AnchorViewModel.self) private var anchorViewModel
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel: PanelManagerViewModel?
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.physicalSafeArea) private var physicalSafeArea

  public init() {}

  public var body: some View {
    ZStack {
      // 1. Central Crosshair (Fixed at center of map viewport)
      MarineCrosshairView(
        color: marineTheme.colors.vectorHDG,
        centerDotColor: marineTheme.colors.destructive
      )

      VStack {
        // 2. Top Sightline Telemetry HUD (Isolated sub-view for 120fps rendering)
        LineOfSightHUDView(chartViewModel: chartViewModel)
          .padding(.top, physicalSafeArea.top + MarineTheme.Spacing.hudCardTopPadding)

        Spacer()

        // 3. Bottom Action Controls & Instruction Prompt
        bottomControlPanel
          .padding(.horizontal, MarineTheme.Spacing.medium)
          .padding(.bottom, MarineTheme.Spacing.overlayCardBottom)
      }
    }
    // CRITICAL: Must ignore all safe areas (not just .top) so that this ZStack's mathematical center
    // perfectly aligns with the MapLibreView beneath it. Otherwise, the crosshair will be offset
    // by the bottom home indicator safe area, causing inaccurate GPS coordinate sampling on confirm.
    .ignoresSafeArea()
  }

  @ViewBuilder
  private var bottomControlPanel: some View {
    MarineActionConfirmationCard(
      title: "Drag map to adjust anchor position",
      onCancel: {
        Logger.anchor.info("User canceled anchor position adjustment")
        anchorViewModel.cancelAdjustAnchor()
        panelManagerViewModel?.openAnchorAlarmPanel()
      },
      onConfirm: {
        let newCoordinate = chartViewModel.centerCoordinate
        Logger.anchor.info("User confirmed new anchor coordinate at (\(newCoordinate.latitude, privacy: .public), \(newCoordinate.longitude, privacy: .public))")
        anchorViewModel.confirmAdjustAnchor(to: newCoordinate)
        panelManagerViewModel?.openAnchorAlarmPanel()
      },
      onHeightChange: { height in
        panelManagerViewModel?.actionConfirmationCardHeight = height
        panelManagerViewModel?.actionConfirmationCardBottomPadding = MarineTheme.Spacing.overlayCardBottom
      }
    )
  }
}

// MARK: - 120fps Throttled Sightline HUD Sub-View

/// Technical Design Choice: Render Performance & SwiftUI Throttling
/// Isolates state observation of `chartViewModel.centerCoordinate` (which mutates at 60-120Hz during map panning).
/// By encapsulating the distance and bearing computation inside this micro sub-view, only text values re-render per frame,
/// leaving parent layout containers and action buttons unaffected.
fileprivate struct LineOfSightHUDView: View {
  let chartViewModel: ChartViewModel
  @Environment(\.locale) private var locale

  var body: some View {
    let centerCoord = chartViewModel.centerCoordinate
    let vesselCoord = chartViewModel.currentCoordinate

    let distance = vesselCoord?.distance(to: centerCoord)
    let bearing = vesselCoord?.greatCircleBearing(to: centerCoord)

    let distanceString = distance?.marineContextualDistanceFormatted(locale: locale) ?? "---"
    let bearingString = bearing?.marineBearingFormatted ?? "---"

    let items = [
      MarineTelemetryItem(label: "DISTANCE", value: distanceString, isPlaceholder: distance == nil),
      MarineTelemetryItem(label: "BEARING", value: bearingString, isPlaceholder: bearing == nil)
    ]

    MarineTelemetryHUDCard(items: items)
  }
}
