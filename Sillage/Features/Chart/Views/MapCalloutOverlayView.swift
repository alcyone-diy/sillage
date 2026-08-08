//
//  MapCalloutOverlayView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation

/// A floating Apple-style callout overlay view rendered over MapLibreView.
/// Features an exact target crosshair at the screen coordinate and an offset material menu card
/// displaying live bearing & distance telemetry and contextual marine action buttons.
struct MapCalloutOverlayView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.waypointService) private var waypointService
  @Environment(PanelManagerViewModel.self) private var panelManager
  @Environment(AppViewModel.self) private var appViewModel
  
  @Bindable var calloutViewModel: MapCalloutViewModel
  var chartViewModel: ChartViewModel
  
  var body: some View {
    if calloutViewModel.isCalloutVisible {
      GeometryReader { geometry in
        let vesselCoord = chartViewModel.currentCoordinate
        let bearing = calloutViewModel.bearing(from: vesselCoord)
        let distance = calloutViewModel.distance(from: vesselCoord)
        
        let screenPoint = calloutViewModel.screenPoint
        let cardWidth: CGFloat = 260
        
        // Determine whether to place the card above or below the crosshair reticle
        let isNearTop = screenPoint.y < 160
        let cardY = isNearTop ? screenPoint.y + 105 : screenPoint.y - 105
        let cardX = min(max(screenPoint.x, cardWidth / 2 + 16), geometry.size.width - cardWidth / 2 - 16)
        
        ZStack {
          // 1. Target Crosshair Reticle (Displayed only when targeting empty map space)
          if calloutViewModel.targetWaypointID == nil {
            targetCrosshairView
              .position(x: screenPoint.x, y: screenPoint.y)
          }
          
          // 2. Floating Callout Menu Card (Offset above/below target point)
          calloutCardView(bearing: bearing, distance: distance)
            .frame(width: cardWidth)
            .background(
              .regularMaterial,
              in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(marineTheme.colors.border.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
            .position(x: cardX, y: cardY)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
      }
      .ignoresSafeArea()
    }
  }
  
  // MARK: - Target Crosshair Reticle
  
  private var targetCrosshairView: some View {
    ZStack {
      // Outer reticle ring with white stroke shadow for visibility over dark/light charts
      Circle()
        .stroke(Color.white, lineWidth: 3)
        .frame(width: 26, height: 26)
        .shadow(color: .black.opacity(0.4), radius: 2)
      
      Circle()
        .stroke(marineTheme.colors.primary, lineWidth: 2)
        .frame(width: 26, height: 26)
      
      // Crosshair tick marks (+)
      Rectangle()
        .fill(marineTheme.colors.primary)
        .frame(width: 1.5, height: 32)
      
      Rectangle()
        .fill(marineTheme.colors.primary)
        .frame(width: 32, height: 1.5)
      
      // Center focal dot
      Circle()
        .fill(marineTheme.colors.primary)
        .frame(width: 6, height: 6)
    }
  }
  
  // MARK: - Callout Card Content
  
  private func calloutCardView(bearing: Measurement<UnitAngle>?, distance: Measurement<UnitLength>?) -> some View {
    VStack(spacing: 0) {
      // Telemetry Header (Bearing & Distance)
      HStack(spacing: 0) {
        // Bearing Cell
        VStack(spacing: 2) {
          Text("BEARING")
            .font(.caption2.bold())
            .foregroundColor(marineTheme.colors.textSecondary)
          
          if let brg = bearing {
            let degValue = Int(brg.converted(to: .degrees).value.rounded())
            let normalizedDeg = (degValue % 360 + 360) % 360
            Text(String(format: "%03d°", normalizedDeg))
              .font(.system(.callout, design: .monospaced).bold())
              .foregroundColor(marineTheme.colors.textPrimary)
          } else {
            Text("---°")
              .font(.system(.callout, design: .monospaced).bold())
              .foregroundColor(marineTheme.colors.textSecondary)
          }
        }
        .frame(maxWidth: .infinity)
        
        Divider()
          .frame(height: 32)
        
        // Distance Cell
        VStack(spacing: 2) {
          Text("DISTANCE")
            .font(.caption2.bold())
            .foregroundColor(marineTheme.colors.textSecondary)
          
          if let dist = distance {
            Text(formatDistance(dist))
              .font(.system(.callout, design: .monospaced).bold())
              .foregroundColor(marineTheme.colors.textPrimary)
          } else {
            Text("--")
              .font(.system(.callout, design: .monospaced).bold())
              .foregroundColor(marineTheme.colors.textSecondary)
          }
        }
        .frame(maxWidth: .infinity)
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 8)
      
      Divider()
      
      // Contextual Actions
      VStack(spacing: 0) {
        if let waypointID = calloutViewModel.targetWaypointID {
          let isSelected = chartViewModel.goToWaypointID == waypointID
          
          Button {
            Task { @MainActor in
              if isSelected {
                waypointService?.setDestination(waypointID: nil)
              } else {
                waypointService?.setDestination(waypointID: waypointID)
              }
            }
            calloutViewModel.dismiss()
          } label: {
            actionRow(
              title: isSelected ? String(localized: "Deselect") : String(localized: "Select"),
              systemImage: isSelected ? MarineIcon.deselect.rawValue : MarineIcon.select.rawValue
            )
          }
          .buttonStyle(.plain)
          
          Divider()
          
          Button {
            Task { @MainActor in
              panelManager.commandPath = [.waypoints, .waypointDetail(waypointID)]
              panelManager.openPanel(.command)
            }
            calloutViewModel.dismiss()
          } label: {
            actionRow(
              title: String(localized: "Show Details"),
              systemImage: MarineIcon.details.rawValue
            )
          }
          .buttonStyle(.plain)
          
        } else {
          Button {
            guard let targetCoord = calloutViewModel.targetCoordinate else { return }
            Task { @MainActor in
              var defaultName: String? = nil
              if let service = waypointService {
                defaultName = await service.generateDefaultName()
              }
              let draftCoord = CoordinateWrapper(coordinate: targetCoord, defaultName: defaultName)
              appViewModel.waypointDraft = draftCoord
            }
            calloutViewModel.dismiss()
          } label: {
            actionRow(
              title: String(localized: "Create Waypoint…"),
              systemImage: MarineIcon.waypoint.rawValue
            )
          }
          .buttonStyle(.plain)
          
          if chartViewModel.goToWaypointID != nil {
            Divider()
            
            Button {
              Task { @MainActor in
                waypointService?.setDestination(waypointID: nil)
              }
              calloutViewModel.dismiss()
            } label: {
              actionRow(
                title: String(localized: "Deselect Target"),
                systemImage: MarineIcon.deselect.rawValue
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
  
  private func actionRow(title: String, systemImage: String, isDestructive: Bool = false) -> some View {
    HStack {
      Text(title)
        .font(.subheadline)
        .foregroundColor(isDestructive ? .red : marineTheme.colors.textPrimary)
      Spacer()
      Image(systemName: systemImage)
        .font(.subheadline)
        .foregroundColor(isDestructive ? .red : marineTheme.colors.textPrimary)
    }
    .padding(.horizontal, 14)
    .frame(height: 44)
    .contentShape(Rectangle())
  }
  
  private func formatDistance(_ distance: Measurement<UnitLength>) -> String {
    let meters = distance.converted(to: .meters).value
    if meters < 185.2 {
      let mMeasurement = Measurement(value: meters, unit: UnitLength.meters)
      return mMeasurement.formatted(
        .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
      )
    } else {
      let nmMeasurement = distance.converted(to: .nauticalMiles)
      return nmMeasurement.formatted(
        .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2)))
      )
    }
  }
}
