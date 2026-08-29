//
//  MapCalloutView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation
import OSLog

/// A native contextual bottom dialog sheet overlay view rendered for map targets.
/// Displays an exact target crosshair at the screen coordinate when targeting empty map space,
/// and presents a self-sizing native bottom sheet (.presentationDetents([.height(...)]) with
/// .presentationDragIndicator(.visible) and .presentationBackgroundInteraction(.enabled))
/// displaying live bearing & distance telemetry and contextual marine action buttons.
struct MapCalloutView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.waypointService) private var waypointService
  @Environment(PanelManagerViewModel.self) private var panelManager
  @Environment(AppViewModel.self) private var appViewModel
  @Environment(\.locale) private var locale
  
  @Bindable var calloutViewModel: MapCalloutViewModel
  var chartViewModel: ChartViewModel
  
  @State private var measuredHeight: CGFloat = 220
  
  var body: some View {
    ZStack {
      // 1. Target Crosshair Reticle (Displayed only when targeting empty map space)
      if calloutViewModel.isCalloutVisible && calloutViewModel.targetWaypointID == nil {
        MarineCrosshairView()
          .position(x: calloutViewModel.screenPoint.x, y: calloutViewModel.screenPoint.y)
      }
    }
    .sheet(isPresented: $calloutViewModel.isCalloutVisible) {
      calloutSheetContent
        .onGeometryChange(for: CGFloat.self) { proxy in
          proxy.size.height
        } action: { newHeight in
          if newHeight > 0 {
            measuredHeight = newHeight
            calloutViewModel.ensureVisible(sheetHeight: newHeight)
          }
        }
        .presentationDetents([.height(measuredHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(measuredHeight)))
    }
  }
  
  // MARK: - Callout Sheet Content
  
  private var calloutSheetContent: some View {
    VStack(spacing: MarineTheme.Spacing.small) {
      // 1. Contextual Header (Waypoint name or Target coordinate)
      headerView
        .padding(.top, MarineTheme.Spacing.small)
        .padding(.horizontal, MarineTheme.Spacing.medium)
      
      // 2. Telemetry Section (BTW & RNG)
      let vesselCoord = chartViewModel.currentCoordinate
      let bearing = calloutViewModel.bearing(from: vesselCoord)
      let distance = calloutViewModel.distance(from: vesselCoord)
      
      telemetryBar(bearing: bearing, distance: distance)
        .padding(.horizontal, MarineTheme.Spacing.medium)
      
      Divider()
        .padding(.horizontal, MarineTheme.Spacing.small)
      
      // 3. Contextual Action Buttons
      actionsView
        .padding(.horizontal, MarineTheme.Spacing.medium)
        .padding(.bottom, MarineTheme.Spacing.small)
    }
    .frame(maxWidth: .infinity)
  }
  
  // MARK: - Subviews
  
  @ViewBuilder
  private var headerView: some View {
    if let waypointID = calloutViewModel.targetWaypointID,
       let waypoint = waypointService?.currentWaypoints.first(where: { $0.id == waypointID }) {
      HStack(spacing: MarineTheme.Spacing.small) {
        Image(marineIcon: .waypoint)
          .foregroundColor(marineTheme.colors.primary)
          .marineFont(.body)
        Text(waypoint.name)
          .marineFont(.headline)
          .foregroundColor(marineTheme.colors.textPrimary)
          .lineLimit(1)
        Spacer()
      }
    } else {
      HStack(spacing: MarineTheme.Spacing.small) {
        Image(marineIcon: .crosshair)
          .foregroundColor(marineTheme.colors.primary)
          .marineFont(.body)
        if let formatted = calloutViewModel.formattedCoordinate {
          Text(formatted)
            .marineFont(.subheadline)
            .foregroundColor(marineTheme.colors.textPrimary)
            .lineLimit(1)
        } else {
          Text("Target Position")
            .marineFont(.headline)
            .foregroundColor(marineTheme.colors.textPrimary)
        }
        Spacer()
      }
    }
  }
  
  private func telemetryBar(bearing: Measurement<UnitAngle>?, distance: Measurement<UnitLength>?) -> some View {
    HStack(spacing: 0) {
      // Bearing Cell (BTW)
      VStack(spacing: MarineTheme.Spacing.tiny / 2) {
        Text("BTW")
          .bold()
          .marineFont(.caption)
          .foregroundColor(marineTheme.colors.textSecondary)
        
        if let brg = bearing {
          Text(brg.marineBearingFormatted)
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
      .frame(maxWidth: .infinity)
      
      Divider()
        .frame(height: MarineTheme.Metrics.calloutDividerHeight)
      
      // Distance Cell (RNG)
      VStack(spacing: MarineTheme.Spacing.tiny / 2) {
        Text("RNG")
          .bold()
          .marineFont(.caption)
          .foregroundColor(marineTheme.colors.textSecondary)
        
        if let dist = distance {
          Text(dist.marineContextualDistanceFormatted(locale: locale))
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
    .padding(.vertical, MarineTheme.Spacing.small)
    .background(
      marineTheme.colors.surfaceBackground,
      in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
    )
  }
  
  @ViewBuilder
  private var actionsView: some View {
    if let waypointID = calloutViewModel.targetWaypointID {
      let isSelected = chartViewModel.goToWaypointID == waypointID
      
      VStack(spacing: MarineTheme.Spacing.small) {
        Button {
          Task { @MainActor [weak waypointService, weak calloutViewModel] in
            guard let waypointService, let calloutViewModel else { return }
            if isSelected {
              Logger.navigation.info("Deselecting destination waypoint ID: \(waypointID, privacy: .public)")
              waypointService.setDestination(waypointID: nil)
            } else {
              Logger.navigation.info("Setting destination waypoint ID: \(waypointID, privacy: .public)")
              waypointService.setDestination(waypointID: waypointID)
            }
            calloutViewModel.dismiss()
          }
        } label: {
          actionRow(
            title: isSelected ? String(localized: "Deselect") : String(localized: "Select"),
            systemImage: isSelected ? MarineIcon.deselect.rawValue : MarineIcon.select.rawValue
          )
        }
        .buttonStyle(.plain)
        
        Divider()
        
        Button {
          Task { @MainActor [weak panelManager, weak calloutViewModel] in
            guard let panelManager, let calloutViewModel else { return }
            Logger.navigation.info("Opening waypoint detail for ID: \(waypointID, privacy: .public)")
            panelManager.commandPath = [.waypoints, .waypointDetail(waypointID)]
            panelManager.openPanel(.command)
            calloutViewModel.dismiss()
          }
        } label: {
          actionRow(
            title: String(localized: "Show Details"),
            systemImage: MarineIcon.details.rawValue
          )
        }
        .buttonStyle(.plain)
      }
    } else {
      VStack(spacing: MarineTheme.Spacing.small) {
        Button {
          guard let targetCoord = calloutViewModel.targetCoordinate else { return }
          Task { @MainActor [weak waypointService, weak appViewModel, weak calloutViewModel] in
            guard let appViewModel, let calloutViewModel else { return }
            var defaultName: String? = nil
            if let service = waypointService {
              defaultName = await service.generateDefaultName()
            }
            Logger.navigation.info("Initiating waypoint creation draft from map target")
            let draftCoord = CoordinateWrapper(coordinate: targetCoord, defaultName: defaultName)
            calloutViewModel.dismiss()
            appViewModel.waypointDraft = draftCoord
          }
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
            Task { @MainActor [weak waypointService, weak calloutViewModel] in
              guard let waypointService, let calloutViewModel else { return }
              Logger.navigation.info("Deselecting active target from map callout")
              waypointService.setDestination(waypointID: nil)
              calloutViewModel.dismiss()
            }
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
}
