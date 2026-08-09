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
        let cardWidth = MarineTheme.Metrics.calloutCardWidth
        
        // Determine whether to place the card above or below the crosshair reticle
        let isNearTop = screenPoint.y < MarineTheme.Metrics.topToolbarClearance
        let verticalOffset = MarineTheme.Metrics.calloutVerticalOffset
        let cardY = isNearTop ? screenPoint.y + verticalOffset : screenPoint.y - verticalOffset
        let horizontalMargin = MarineTheme.Spacing.medium
        let cardX = min(max(screenPoint.x, cardWidth / 2 + horizontalMargin), geometry.size.width - cardWidth / 2 - horizontalMargin)
        
        ZStack {
          // 1. Target Crosshair Reticle (Displayed only when targeting empty map space)
          if calloutViewModel.targetWaypointID == nil {
            MarineCrosshairView()
              .position(x: screenPoint.x, y: screenPoint.y)
          }
          
          // 2. Floating Callout Menu Card (Offset above/below target point)
          calloutCardView(bearing: bearing, distance: distance)
            .frame(width: cardWidth)
            .background(
              .regularMaterial,
              in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
            )
            .overlay(
              RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
                .stroke(marineTheme.colors.border.opacity(0.4), lineWidth: MarineTheme.Metrics.borderWidth / 2)
            )
            .shadow(color: Color.black.opacity(0.15), radius: MarineTheme.Metrics.shadowRadius * 3, x: 0, y: MarineTheme.Metrics.shadowOffset * 3)
            .position(x: cardX, y: cardY)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
      }
      .ignoresSafeArea()
    }
  }
  
  // MARK: - Callout Card Content
  
  private func calloutCardView(bearing: Measurement<UnitAngle>?, distance: Measurement<UnitLength>?) -> some View {
    VStack(spacing: 0) {
      // Telemetry Header (Bearing & Distance)
      HStack(spacing: 0) {
        // Bearing Cell
        VStack(spacing: MarineTheme.Spacing.tiny / 2) {
          Text("BTW")
            .bold()
            .marineFont(.caption)
            .foregroundColor(marineTheme.colors.textSecondary)
          
          if let brg = bearing {
            let degValue = Int(brg.converted(to: .degrees).value.rounded())
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
        .frame(maxWidth: .infinity)
        
        Divider()
          .frame(height: MarineTheme.Metrics.calloutDividerHeight)
        
        // Distance Cell
        VStack(spacing: MarineTheme.Spacing.tiny / 2) {
          Text("RNG")
            .bold()
            .marineFont(.caption)
            .foregroundColor(marineTheme.colors.textSecondary)
          
          if let dist = distance {
            Text(formatDistance(dist))
              .monospacedDigit()
              .bold()
              .marineFont(.body)
              .foregroundColor(marineTheme.colors.textPrimary)
          } else {
            Text("--")
              .monospacedDigit()
              .bold()
              .marineFont(.body)
              .foregroundColor(marineTheme.colors.textSecondary)
          }
        }
        .frame(maxWidth: .infinity)
      }
      .padding(.vertical, MarineTheme.Spacing.small + 2)
      .padding(.horizontal, MarineTheme.Spacing.small)
      
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
        .marineFont(.body)
        .foregroundColor(isDestructive ? marineTheme.colors.destructive : marineTheme.colors.textPrimary)
      Spacer()
      Image(systemName: systemImage)
        .marineFont(.body)
        .foregroundColor(isDestructive ? marineTheme.colors.destructive : marineTheme.colors.textPrimary)
    }
    .padding(.horizontal, MarineTheme.Spacing.actionRowHorizontal)
    .frame(minHeight: marineTheme.minTouchTarget)
    .contentShape(Rectangle())
  }
  
  private func formatDistance(_ distance: Measurement<UnitLength>) -> String {
    distance.marineContextualDistanceFormatted()
  }
}
