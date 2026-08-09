//
//  AnchorAdjustOverlayView.swift
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
public struct AnchorAdjustOverlayView: View {
  @Environment(AnchorViewModel.self) private var anchorViewModel
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel: PanelManagerViewModel?
  @Environment(\.marineTheme) private var marineTheme

  public init() {}

  public var body: some View {
    ZStack {
      // 1. Central Crosshair Reticle (Fixed at center of map viewport)
      MarineCrosshairView(
        color: marineTheme.colors.vectorHDG,
        centerDotColor: marineTheme.colors.destructive
      )

      VStack {
        // 2. Top Sightline Telemetry HUD (Isolated sub-view for 120fps rendering)
        LineOfSightHUDView(chartViewModel: chartViewModel)
          .padding(.top, MarineTheme.Spacing.extraLarge * 2) // Safe area clearance below top edge

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
        panelManagerViewModel?.openPanel(.command)
      },
      onConfirm: {
        let newCoordinate = chartViewModel.centerCoordinate
        Logger.anchor.info("User confirmed new anchor coordinate at (\(newCoordinate.latitude, privacy: .public), \(newCoordinate.longitude, privacy: .public))")
        anchorViewModel.confirmAdjustAnchor(to: newCoordinate)
        panelManagerViewModel?.openPanel(.command)
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
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    let centerCoord = chartViewModel.centerCoordinate
    let vesselCoord = chartViewModel.currentCoordinate

    let distance: Measurement<UnitLength>? = {
      guard let vessel = vesselCoord else { return nil }
      return vessel.distance(to: centerCoord)
    }()

    let bearing: Measurement<UnitAngle>? = {
      guard let vessel = vesselCoord else { return nil }
      return vessel.greatCircleBearing(to: centerCoord)
    }()

    HStack(spacing: MarineTheme.Spacing.large) {
      // Distance Telemetry (Uses iOS system unit formatting via marineContextualDistanceFormatted)
      VStack(spacing: MarineTheme.Spacing.tiny / 2) {
        Text("DISTANCE")
          .bold()
          .marineFont(.caption)
          .foregroundColor(marineTheme.colors.textSecondary)

        if let dist = distance {
          Text(dist.marineContextualDistanceFormatted)
            .monospacedDigit()
            .bold()
            .marineFont(.body)
            .foregroundColor(marineTheme.colors.textPrimary)
        } else {
          Text("---")
            .monospacedDigit()
            .bold()
            .marineFont(.body)
            .foregroundColor(marineTheme.colors.textSecondary)
        }
      }

      Divider()
        .frame(height: MarineTheme.Metrics.calloutDividerHeight)

      // Bearing Telemetry
      VStack(spacing: MarineTheme.Spacing.tiny / 2) {
        Text("BEARING")
          .bold()
          .marineFont(.caption)
          .foregroundColor(marineTheme.colors.textSecondary)

        if let brg = bearing {
          let degValue = Int(brg.converted(to: .degrees).value)
          let normalizedDeg = (degValue % 360 + 360) % 360
          Text(String(format: "%03d°", normalizedDeg))
            .monospacedDigit()
            .bold()
            .marineFont(.body)
            .foregroundColor(marineTheme.colors.textPrimary)
        } else {
          Text("---°")
            .monospacedDigit()
            .bold()
            .marineFont(.body)
            .foregroundColor(marineTheme.colors.textSecondary)
        }
      }
    }
    .padding(.horizontal, MarineTheme.Spacing.large)
    .padding(.vertical, MarineTheme.Spacing.medium)
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

