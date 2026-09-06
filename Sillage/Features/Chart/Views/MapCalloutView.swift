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
  
  private var isSheetPresented: Binding<Bool> {
    Binding(
      get: { calloutViewModel.isCalloutVisible || chartViewModel.measureToolViewModel.isActive },
      set: { isPresented in
        if !isPresented {
          calloutViewModel.dismiss()
          chartViewModel.measureToolViewModel.stop()
        }
      }
    )
  }
  
  var body: some View {
    ZStack {
      // Target Crosshair (Displayed only when targeting empty map space and not measuring)
      if calloutViewModel.isCalloutVisible && calloutViewModel.targetWaypointID == nil && !chartViewModel.measureToolViewModel.isActive {
        MarineCrosshairView()
          .position(x: calloutViewModel.screenPoint.x, y: calloutViewModel.screenPoint.y)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .sheet(isPresented: isSheetPresented) {
      calloutSheetContent
        .onGeometryChange(for: CGFloat.self) { proxy in
          proxy.size.height
        } action: { newHeight in
          if newHeight > 0 && abs(measuredHeight - newHeight) > 1.0 {
            measuredHeight = newHeight
            if !chartViewModel.measureToolViewModel.isActive {
              calloutViewModel.ensureVisible(sheetHeight: newHeight)
            }
          }
        }
        .presentationDetents([.height(measuredHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(marineTheme.colors.panelBackground)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(measuredHeight)))
        .interactiveDismissDisabled(chartViewModel.isMapMoving || chartViewModel.measureToolViewModel.isDraggingPin)
    }
  }
  
  // MARK: - Callout Sheet Content
  
  @ViewBuilder
  private var calloutSheetContent: some View {
    VStack(spacing: MarineTheme.Spacing.small) {
      if chartViewModel.measureToolViewModel.isActive {
        measureSheetContent
      } else {
        standardCalloutSheetContent
      }
    }
    .frame(maxWidth: .infinity)
  }
  
  @ViewBuilder
  private var standardCalloutSheetContent: some View {
    // 1. Contextual Header (Waypoint name or Target coordinate)
    headerView
      .padding(.top, MarineTheme.Spacing.small)
      .padding(.horizontal, MarineTheme.Spacing.medium)
    
    // 2. Telemetry Section (BTW & RNG)
    let vesselCoord = chartViewModel.currentCoordinate
    let bearing = calloutViewModel.bearing(from: vesselCoord)
    let distance = calloutViewModel.distance(from: vesselCoord)
    
    standardTelemetryBar(bearing: bearing, distance: distance)
      .padding(.horizontal, MarineTheme.Spacing.medium)
    
    // 3. Contextual Action Buttons
    actionsView
      .padding(.horizontal, MarineTheme.Spacing.medium)
      .padding(.bottom, MarineTheme.Spacing.small)
  }
  
  @ViewBuilder
  private var measureSheetContent: some View {
    let measureVM = chartViewModel.measureToolViewModel
    
    // 1. Contextual Header (Ruler icon + Measure Distance)
    HStack(spacing: MarineTheme.Spacing.small) {
      Spacer()
      Image(marineIcon: .ruler)
        .foregroundColor(marineTheme.colors.primary)
        .marineFont(.body)
      Text("Measure Distance")
        .marineFont(.headline)
        .foregroundColor(marineTheme.colors.textPrimary)
        .lineLimit(1)
      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.top, MarineTheme.Spacing.small)
    .padding(.horizontal, MarineTheme.Spacing.medium)
    
    // 2. Telemetry Section: BRG, RECIPROCAL, RNG (reusing callout telemetry styling)
    measureTelemetryBar(
      bearing: measureVM.bearing,
      reciprocal: measureVM.reciprocalBearing,
      distance: measureVM.distance
    )
    .padding(.horizontal, MarineTheme.Spacing.medium)
    
    // 3. Contextual Actions: Active Pin Selection
    HStack {
      Text("Active Pin")
        .marineFont(.body)
        .foregroundColor(marineTheme.colors.textPrimary)
      Spacer()
      HStack(spacing: MarineTheme.Spacing.small) {
        pinSelectionButton(title: "Pin A", pin: .start, viewModel: measureVM)
        pinSelectionButton(title: "Pin B", pin: .end, viewModel: measureVM)
      }
    }
    .padding(.horizontal, MarineTheme.Spacing.actionRowHorizontal)
    .frame(minHeight: marineTheme.minTouchTarget)
    .background(
      marineTheme.colors.surfaceBackground,
      in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
    )
    .padding(.horizontal, MarineTheme.Spacing.medium)
    
    Text("Drag pins or long press chart to reposition")
      .marineFont(.caption)
      .foregroundColor(marineTheme.colors.textSecondary)
      .padding(.bottom, MarineTheme.Spacing.small)
  }
  
  // MARK: - Subviews
  
  @ViewBuilder
  private var headerView: some View {
    HStack(spacing: MarineTheme.Spacing.small) {
      Spacer()
      if let waypointID = calloutViewModel.targetWaypointID,
         let waypoint = waypointService?.currentWaypoints.first(where: { $0.id == waypointID }) {
        Image(marineIcon: .waypoint)
          .foregroundColor(marineTheme.colors.primary)
          .marineFont(.body)
        Text(waypoint.name)
          .marineFont(.headline)
          .foregroundColor(marineTheme.colors.textPrimary)
          .lineLimit(1)
      } else {
        Image(marineIcon: .crosshair)
          .foregroundColor(marineTheme.colors.primary)
          .marineFont(.body)
        if let formatted = calloutViewModel.formattedCoordinate {
          Text(formatted)
            .monospacedDigit()
            .marineFont(.subheadline)
            .foregroundColor(marineTheme.colors.textPrimary)
            .lineLimit(1)
        } else {
          Text("Target Position")
            .marineFont(.headline)
            .foregroundColor(marineTheme.colors.textPrimary)
        }
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }
  
  private func standardTelemetryBar(bearing: Measurement<UnitAngle>?, distance: Measurement<UnitLength>?) -> some View {
    HStack(spacing: 0) {
      telemetryCell(label: "BTW", value: bearing?.marineBearingFormatted)
      Divider().frame(height: MarineTheme.Metrics.calloutDividerHeight)
      telemetryCell(label: "RNG", value: distance?.marineContextualDistanceFormatted(locale: locale))
    }
    .padding(.vertical, MarineTheme.Spacing.small)
    .background(
      marineTheme.colors.surfaceBackground,
      in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
    )
  }
  
  private func measureTelemetryBar(
    bearing: Measurement<UnitAngle>?,
    reciprocal: Measurement<UnitAngle>?,
    distance: Measurement<UnitLength>?
  ) -> some View {
    HStack(spacing: 0) {
      telemetryCell(label: "BRG", value: bearing?.marineBearingFormatted)
      Divider().frame(height: MarineTheme.Metrics.calloutDividerHeight)
      telemetryCell(label: "RECIPROCAL", value: reciprocal?.marineBearingFormatted)
      Divider().frame(height: MarineTheme.Metrics.calloutDividerHeight)
      telemetryCell(label: "RNG", value: distance?.marineContextualDistanceFormatted(locale: locale))
    }
    .padding(.vertical, MarineTheme.Spacing.small)
    .background(
      marineTheme.colors.surfaceBackground,
      in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
    )
  }
  
  private func telemetryCell(label: LocalizedStringKey, value: String?) -> some View {
    VStack(spacing: MarineTheme.Spacing.tiny / 2) {
      Text(label)
        .bold()
        .marineFont(.caption)
        .foregroundColor(marineTheme.colors.textSecondary)
      
      Text(value ?? "---")
        .monospacedDigit()
        .bold()
        .marineFont(.body)
        .foregroundColor(value != nil ? marineTheme.colors.textPrimary : marineTheme.colors.textSecondary)
    }
    .frame(maxWidth: .infinity)
  }
  
  @ViewBuilder
  private func pinSelectionButton(title: LocalizedStringKey, pin: ActiveMeasurePin, viewModel: MeasureToolViewModel) -> some View {
    let isSelected = viewModel.activePin == pin
    Button {
      viewModel.activePin = pin
      chartViewModel.centerOnMeasurePinIfNeeded(pin)
    } label: {
      HStack(spacing: MarineTheme.Spacing.tiny) {
        Circle()
          .fill(isSelected ? marineTheme.colors.accent : marineTheme.colors.textSecondary)
          .frame(width: 8, height: 8)
        Text(title)
          .bold()
          .marineFont(.subheadline)
          .foregroundColor(isSelected ? marineTheme.colors.textPrimary : marineTheme.colors.textSecondary)
      }
      .padding(.horizontal, MarineTheme.Spacing.small)
      .frame(minHeight: max(36, marineTheme.minTouchTarget - 12))
      .background(
        isSelected ? marineTheme.colors.panelBackground : Color.clear,
        in: Capsule()
      )
      .overlay(
        Capsule()
          .strokeBorder(isSelected ? marineTheme.colors.accent : marineTheme.colors.panelBackground, lineWidth: 1.5)
      )
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
  }
  
  @ViewBuilder
  private var actionsView: some View {
    if let waypointID = calloutViewModel.targetWaypointID {
      let isSelected = chartViewModel.goToWaypointID == waypointID
      
      VStack(spacing: 0) {
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
        
        Divider()
        
        Button {
          guard let targetCoord = calloutViewModel.targetCoordinate else { return }
          Logger.navigation.info("Activating measure tool from waypoint callout")
          calloutViewModel.dismiss()
          chartViewModel.startMeasuring(from: targetCoord)
        } label: {
          actionRow(
            title: String(localized: "Measure Distance…"),
            systemImage: MarineIcon.ruler.rawValue
          )
        }
        .buttonStyle(.plain)
      }
      .background(
        marineTheme.colors.surfaceBackground,
        in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
      )
    } else {
      VStack(spacing: 0) {
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
        
        Divider()
        
        Button {
          guard let targetCoord = calloutViewModel.targetCoordinate else { return }
          Logger.navigation.info("Activating measure tool from map target callout")
          calloutViewModel.dismiss()
          chartViewModel.startMeasuring(from: targetCoord)
        } label: {
          actionRow(
            title: String(localized: "Measure Distance…"),
            systemImage: MarineIcon.ruler.rawValue
          )
        }
        .buttonStyle(.plain)
      }
      .background(
        marineTheme.colors.surfaceBackground,
        in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
      )
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

