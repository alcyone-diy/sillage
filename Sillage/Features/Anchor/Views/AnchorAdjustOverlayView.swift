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
      CrosshairView()
        .allowsHitTesting(false)

      VStack {
        // 2. Top Sightline Telemetry HUD (Isolated sub-view for 120fps rendering)
        LineOfSightHUDView(chartViewModel: chartViewModel)
          .padding(.top, 60) // Safe area clearance below top edge

        Spacer()

        // 3. Bottom Action Controls & Instruction Prompt
        bottomControlPanel
          .padding(.horizontal, MarineTheme.Spacing.medium)
          .padding(.bottom, 40)
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
      }
    )
    .onAppear {
      chartViewModel.isActionConfirmationCardActive = true
    }
    .onDisappear {
      chartViewModel.isActionConfirmationCardActive = false
    }
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

  private static let distanceFormatter: MeasurementFormatter = {
    let formatter = MeasurementFormatter()
    formatter.unitOptions = .providedUnit
    formatter.numberFormatter.maximumFractionDigits = 0
    return formatter
  }()

  var body: some View {
    let centerCoord = chartViewModel.centerCoordinate
    let vesselCoord = chartViewModel.currentCoordinate

    let distance: Measurement<UnitLength>? = {
      guard let vessel = vesselCoord else { return nil }
      let boatLoc = CLLocation(latitude: vessel.latitude, longitude: vessel.longitude)
      let centerLoc = CLLocation(latitude: centerCoord.latitude, longitude: centerCoord.longitude)
      return Measurement(value: boatLoc.distance(from: centerLoc), unit: UnitLength.meters)
    }()

    let bearing: Measurement<UnitAngle>? = {
      guard let vessel = vesselCoord else { return nil }
      return vessel.greatCircleBearing(to: centerCoord)
    }()

    HStack(spacing: MarineTheme.Spacing.large) {
      // Distance Telemetry
      VStack(spacing: 2) {
        Text("DISTANCE")
          .font(.caption2.bold())
          .foregroundColor(marineTheme.colors.textSecondary)

        if let dist = distance {
          Text(Self.distanceFormatter.string(from: dist.converted(to: .meters)))
            .font(.system(.title2, design: .monospaced).bold())
            .foregroundColor(marineTheme.colors.primary)
        } else {
          Text("-- m")
            .font(.system(.title2, design: .monospaced).bold())
            .foregroundColor(marineTheme.colors.textSecondary)
        }
      }

      Divider()
        .frame(height: 30)

      // Bearing Telemetry
      VStack(spacing: 2) {
        Text("BEARING")
          .font(.caption2.bold())
          .foregroundColor(marineTheme.colors.textSecondary)

        if let brg = bearing {
          let degValue = Int(brg.converted(to: .degrees).value)
          Text(String(format: "%03d°", degValue))
            .font(.system(.title2, design: .monospaced).bold())
            .foregroundColor(marineTheme.colors.primary)
        } else {
          Text("---°")
            .font(.system(.title2, design: .monospaced).bold())
            .foregroundColor(marineTheme.colors.textSecondary)
        }
      }
    }
    .padding(.horizontal, MarineTheme.Spacing.large)
    .padding(.vertical, MarineTheme.Spacing.medium)
    .background(Material.ultraThinMaterial)
    .cornerRadius(MarineTheme.Metrics.cornerRadius)
    .overlay(
      RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius)
        .stroke(marineTheme.colors.primary.opacity(0.5), lineWidth: 1.0)
    )
    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
  }
}

// MARK: - Central Crosshair Reticle

fileprivate struct CrosshairView: View {
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    ZStack {
      // Outer Target Circle
      Circle()
        .stroke(marineTheme.colors.vectorHDG, lineWidth: 2.0)
        .frame(width: 44, height: 44)

      // Inner Center Dot
      Circle()
        .fill(marineTheme.colors.destructive)
        .frame(width: 6, height: 6)

      // Horizontal Line
      Rectangle()
        .fill(marineTheme.colors.vectorHDG)
        .frame(width: 60, height: 1.5)

      // Vertical Line
      Rectangle()
        .fill(marineTheme.colors.vectorHDG)
        .frame(width: 1.5, height: 60)
    }
    .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 2)
  }
}
