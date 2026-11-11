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
/// Displays an interactive inverted teardrop map pin at the screen coordinate when targeting empty map space,
/// and presents a self-sizing native bottom sheet (.presentationDetents([.height(...)]) with
/// .presentationDragIndicator(.visible) and .presentationBackgroundInteraction(.enabled))
/// displaying live bearing & distance telemetry and contextual marine action buttons.
struct MapCalloutView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(WaypointService.self) private var waypointService
  @Environment(PanelManagerViewModel.self) private var panelManager
  @Environment(AppViewModel.self) private var appViewModel
  @Environment(\.locale) private var locale
  
  @Bindable var calloutViewModel: MapCalloutViewModel
  var chartViewModel: ChartViewModel
  
  @State private var measuredHeight: CGFloat = 220
  @State private var hasMeasuredInitialHeight: Bool = false
  @State private var isCopied: Bool = false
  @State private var copyActionCount: Int = 0
  
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
  
  private func notifySheetHeightChanged(_ height: CGFloat) {
    chartViewModel.measureToolViewModel.ensureVisible(sheetHeight: height)
    calloutViewModel.ensureVisible(sheetHeight: height)
  }

  private func updateMeasuredHeight(_ newHeight: CGFloat) {
    guard newHeight > 0 else { return }
    let shouldAnimate = hasMeasuredInitialHeight
    hasMeasuredInitialHeight = true
    guard abs(measuredHeight - newHeight) > 1.0 else { return }
    if shouldAnimate {
      withAnimation(.snappy(duration: 0.25)) {
        measuredHeight = newHeight
      }
    } else {
      measuredHeight = newHeight
    }
    notifySheetHeightChanged(newHeight)
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.clear
          .allowsHitTesting(false)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Aiming crosshair for contextual map target selection (visible once centering flight completes).
        // Kept permanently mounted in the view hierarchy so its CALayer and shadow buffer are pre-warmed,
        // guaranteeing a 0-frame opacity toggle in the exact same CATransaction as MapLibre layer hiding.
        let isSwiftUICrosshairVisible =
          calloutViewModel.isCalloutVisible &&
          calloutViewModel.targetWaypointID == nil &&
          !calloutViewModel.isCentering &&
          calloutViewModel.aimingCoordinate == nil &&
          !chartViewModel.measureToolViewModel.isActive

        MarineCrosshairView.targetAiming(theme: marineTheme)
          .position(
            x: proxy.size.width / 2.0,
            y: proxy.size.height * AppConstants.Map.aimingCrosshairYFraction
          )
          .opacity(isSwiftUICrosshairVisible ? 1.0 : 0.0)
          .transaction { $0.disablesAnimations = true }
          .allowsHitTesting(false)
      }
    }
    .sheet(isPresented: isSheetPresented) {
      calloutSheetContent
        .presentationDetents([.height(measuredHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(marineTheme.colors.panelBackground)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(measuredHeight)))
        .interactiveDismissDisabled(chartViewModel.isMapMoving || chartViewModel.measureToolViewModel.isDraggingPin || calloutViewModel.aimingCoordinate != nil)
    }
  }
  
  // MARK: - Callout Sheet Content
  
  @ViewBuilder
  private var calloutSheetContent: some View {
    Group {
      if chartViewModel.measureToolViewModel.isActive {
        measuredRootContainer {
          measureSheetContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      } else {
        NavigationStack {
          measuredRootContainer {
            standardCalloutSheetContent
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .background(marineTheme.colors.panelBackground)
          .toolbarVisibility(.hidden, for: .navigationBar)
          .navigationDestination(isPresented: $calloutViewModel.isPointInfoPresented) {
            pointInfoDestination
          }
        }
        .containerBackground(marineTheme.colors.panelBackground, for: .navigation)
      }
    }
    .onAppear {
      notifySheetHeightChanged(measuredHeight)
    }
    .onDisappear {
      hasMeasuredInitialHeight = false
    }
  }

  @ViewBuilder
  private func measuredRootContainer<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(spacing: MarineTheme.Spacing.medium) {
      content()
    }
    .padding(.horizontal, MarineTheme.Spacing.medium)
    .padding(.top, MarineTheme.Spacing.small)
    .padding(.bottom, MarineTheme.Spacing.medium)
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.height
    } action: { newHeight in
      updateMeasuredHeight(newHeight)
    }
  }
  
  // MARK: - Standard Callout Content
  
  @ViewBuilder
  private var standardCalloutSheetContent: some View {
    // 1. Contextual Header (Waypoint name or Target coordinate + Close button)
    headerView
    
    // 2. Telemetry Section (BTW & RNG)
    let vesselCoord = chartViewModel.currentCoordinate
    let bearing = calloutViewModel.bearing(from: vesselCoord)
    let distance = calloutViewModel.distance(from: vesselCoord)
    
    standardTelemetryBar(bearing: bearing, distance: distance)
    
    // 3. Contextual Action Buttons
    actionsView
  }
  
  // MARK: - Measure Tool Content
  
  @ViewBuilder
  private var measureSheetContent: some View {
    let measureVM = chartViewModel.measureToolViewModel
    
    // 1. Contextual Header (Ruler icon + Measure Distance + Close button)
    measureHeaderView
    
    // 2. Telemetry Section: BRG, RECIPROCAL, RNG
    measureTelemetryBar(
      bearing: measureVM.bearing,
      reciprocal: measureVM.reciprocalBearing,
      distance: measureVM.distance
    )
    
    // 3. Contextual Actions: Active Pin Selection (Pin A / Pin B)
    HStack(spacing: MarineTheme.Spacing.small) {
      measurePinButton(title: "Pin A", pin: .start, viewModel: measureVM)
      measurePinButton(title: "Pin B", pin: .end, viewModel: measureVM)
    }
  }
  
  // MARK: - Point Information Content
  
  @ViewBuilder
  private var pointInfoDestination: some View {
    VStack(spacing: 0) {
      pointInfoHeaderView
        .padding(.horizontal, MarineTheme.Spacing.medium)
        .padding(.top, MarineTheme.Spacing.small)
        .padding(.bottom, MarineTheme.Spacing.medium)
      
      ScrollView {
        VStack(spacing: MarineTheme.Spacing.medium) {
          if let targetCoord = calloutViewModel.targetCoordinate {
            gpsPositionSection(coordinate: targetCoord)
          }
        }
        .padding(.horizontal, MarineTheme.Spacing.medium)
        .padding(.bottom, MarineTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(marineTheme.colors.panelBackground)
    .toolbarVisibility(.hidden, for: .navigationBar)
  }

  @ViewBuilder
  private var pointInfoHeaderView: some View {
    HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
      backButton {
        calloutViewModel.dismissPointInfo()
      }
      
      Spacer(minLength: MarineTheme.Spacing.small)
      
      closeButton {
        calloutViewModel.dismiss()
      }
    }
    .overlay {
      Text("Point Information")
        .marineFont(.headline)
        .foregroundColor(marineTheme.colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
        .padding(.horizontal, marineTheme.minTouchTarget + MarineTheme.Spacing.small)
    }
  }
  
  @ViewBuilder
  private func gpsPositionSection(coordinate: CLLocationCoordinate2D) -> some View {
    let formattedText = coordinate.formatted(.marineCoordinate)
    
    HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
      VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny / 2) {
        Text("GPS POSITION")
          .marineFont(.instrumentLabel)
          .foregroundColor(marineTheme.colors.textSecondary)
        
        Text(verbatim: formattedText)
          .monospacedDigit()
          .marineFont(.headline)
          .bold()
          .foregroundColor(marineTheme.colors.textPrimary)
          .lineLimit(2)
          .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
      }
      
      Spacer(minLength: MarineTheme.Spacing.small)
      
      Button {
        copyCoordinateToClipboard(formattedText)
      } label: {
        Image(marineIcon: isCopied ? .save : .copy)
          .marineFont(.body)
          .bold(isCopied)
          .foregroundColor(isCopied ? marineTheme.colors.primary : marineTheme.colors.textSecondary)
          .contentTransition(.symbolEffect(.replace))
          .frame(minWidth: marineTheme.minTouchTarget, minHeight: marineTheme.minTouchTarget)
          .background(
            marineTheme.colors.panelBackground,
            in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isCopied ? Text("Coordinates copied") : Text("Copy coordinates"))
    }
    .padding(MarineTheme.Spacing.small)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      marineTheme.colors.surfaceBackground,
      in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
    )
    .contextMenu {
      Button {
        copyCoordinateToClipboard(formattedText)
      } label: {
        Label("Copy Coordinates", marineIcon: .copy)
      }
    }
    .task(id: copyActionCount) {
      guard copyActionCount > 0 else { return }
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      withAnimation(.easeInOut(duration: 0.2)) {
        isCopied = false
      }
      copyActionCount = 0
    }
    .onDisappear {
      isCopied = false
      copyActionCount = 0
    }
  }
  
  private func copyCoordinateToClipboard(_ text: String) {
    UIPasteboard.general.string = text
    let feedback = UIImpactFeedbackGenerator(style: .medium)
    feedback.impactOccurred()
    withAnimation(.easeInOut(duration: 0.2)) {
      isCopied = true
    }
    copyActionCount += 1
  }
  
  // MARK: - Header Views
  
  @ViewBuilder
  private var headerView: some View {
    if let waypointID = calloutViewModel.targetWaypointID,
       let waypoint = waypointService.currentWaypoints.first(where: { $0.id == waypointID }) {
      calloutHeader(
        icon: .waypoint,
        title: Text(waypoint.name),
        subtitle: Text(waypoint.coordinate.formatted(.marineCoordinate)),
        onClose: { calloutViewModel.dismiss() }
      )
    } else {
      calloutHeader(
        icon: .crosshair,
        title: Text(verbatim: calloutViewModel.formattedCoordinate ?? "---"),
        subtitle: nil,
        onInfo: {
          calloutViewModel.presentPointInfo()
        },
        onClose: { calloutViewModel.dismiss() }
      )
    }
  }
  
  @ViewBuilder
  private var measureHeaderView: some View {
    calloutHeader(
      icon: .ruler,
      title: Text("Measure Distance"),
      subtitle: Text("Drag pins or long press chart to reposition"),
      onClose: { chartViewModel.measureToolViewModel.stop() }
    )
  }
  
  @ViewBuilder
  private func calloutHeader(
    icon: MarineIcon,
    title: Text,
    subtitle: Text?,
    onInfo: (() -> Void)? = nil,
    onClose: @escaping () -> Void
  ) -> some View {
    HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
      HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
        headerIconBadge(icon: icon)
        
        VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny / 2) {
          title
            .monospacedDigit()
            .marineFont(.headline)
            .foregroundColor(marineTheme.colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
          
          if let subtitle {
            subtitle
              .monospacedDigit()
              .marineFont(.subheadline)
              .foregroundColor(marineTheme.colors.textSecondary)
              .lineLimit(1)
              .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
          }
        }
      }
      
      Spacer(minLength: MarineTheme.Spacing.small)
      
      if let onInfo {
        infoButton(onInfo: onInfo)
      }
      
      closeButton(onClose: onClose)
    }
  }
  
  @ViewBuilder
  private func headerIconBadge(icon: MarineIcon) -> some View {
    let size = marineTheme.metrics.calloutHeaderBadgeSize
    ZStack {
      Circle()
        .fill(marineTheme.colors.primary.opacity(MarineTheme.Metrics.badgeBackgroundOpacity))
        .frame(width: size, height: size)
      Image(marineIcon: icon)
        .foregroundColor(marineTheme.colors.primary)
        .marineFont(.body)
    }
  }
  
  @ViewBuilder
  private func backButton(onBack: @escaping () -> Void) -> some View {
    let iconCircleSize = marineTheme.metrics.closeButtonCircleSize
    Button(action: onBack) {
      Image(systemName: "chevron.left")
        .marineFont(.caption)
        .bold()
        .foregroundColor(marineTheme.colors.textSecondary)
        .frame(width: iconCircleSize, height: iconCircleSize)
        .background(marineTheme.colors.surfaceBackground, in: Circle())
    }
    .buttonStyle(.plain)
    .frame(minWidth: marineTheme.minTouchTarget, minHeight: marineTheme.minTouchTarget)
    .contentShape(Rectangle())
    .accessibilityLabel(Text("Back"))
  }

  @ViewBuilder
  private func infoButton(onInfo: @escaping () -> Void) -> some View {
    let iconCircleSize = marineTheme.metrics.closeButtonCircleSize
    Button(action: onInfo) {
      Image(marineIcon: .details)
        .marineFont(.caption)
        .bold()
        .foregroundColor(marineTheme.colors.textSecondary)
        .frame(width: iconCircleSize, height: iconCircleSize)
        .background(marineTheme.colors.surfaceBackground, in: Circle())
    }
    .buttonStyle(.plain)
    .frame(minWidth: marineTheme.minTouchTarget, minHeight: marineTheme.minTouchTarget)
    .contentShape(Rectangle())
    .accessibilityLabel(Text("Information"))
  }

  @ViewBuilder
  private func closeButton(onClose: @escaping () -> Void) -> some View {
    let iconCircleSize = marineTheme.metrics.closeButtonCircleSize
    Button(action: onClose) {
      Image(marineIcon: .close)
        .marineFont(.caption)
        .bold()
        .foregroundColor(marineTheme.colors.textSecondary)
        .frame(width: iconCircleSize, height: iconCircleSize)
        .background(marineTheme.colors.surfaceBackground, in: Circle())
    }
    .buttonStyle(.plain)
    .frame(minWidth: marineTheme.minTouchTarget, minHeight: marineTheme.minTouchTarget)
    .contentShape(Rectangle())
    .accessibilityLabel(Text("Close"))
  }
  
  // MARK: - Telemetry Views
  
  private func standardTelemetryBar(bearing: Measurement<UnitAngle>?, distance: Measurement<UnitLength>?) -> some View {
    HStack(spacing: MarineTheme.Spacing.small) {
      telemetryCard(label: "BTW", value: bearing?.marineBearingFormatted)
      telemetryCard(label: "RNG", value: distance?.marineContextualDistanceFormatted(locale: locale))
    }
  }
  
  private func measureTelemetryBar(
    bearing: Measurement<UnitAngle>?,
    reciprocal: Measurement<UnitAngle>?,
    distance: Measurement<UnitLength>?
  ) -> some View {
    HStack(spacing: MarineTheme.Spacing.small) {
      telemetryCard(label: "BRG", value: bearing?.marineBearingFormatted)
      telemetryCard(label: "RECIPROCAL", value: reciprocal?.marineBearingFormatted)
      telemetryCard(label: "RNG", value: distance?.marineContextualDistanceFormatted(locale: locale))
    }
  }
  
  private func telemetryCard(label: LocalizedStringKey, value: String?) -> some View {
    VStack(spacing: MarineTheme.Spacing.tiny / 2) {
      Text(label)
        .marineFont(.instrumentLabel)
        .foregroundColor(marineTheme.colors.textSecondary)
      
      Text(verbatim: value ?? "---")
        .monospacedDigit()
        .marineFont(.instrumentData)
        .foregroundColor(value != nil ? marineTheme.colors.textPrimary : marineTheme.colors.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, MarineTheme.Spacing.small)
    .background(
      marineTheme.colors.surfaceBackground,
      in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
    )
  }
  
  // MARK: - Pin Selection
  
  @ViewBuilder
  private func measurePinButton(title: LocalizedStringKey, pin: ActiveMeasurePin, viewModel: MeasureToolViewModel) -> some View {
    let isSelected = viewModel.activePin == pin
    Button {
      viewModel.activePin = pin
      chartViewModel.centerOnMeasurePinIfNeeded(pin)
    } label: {
      HStack(spacing: MarineTheme.Spacing.small) {
        Circle()
          .fill(isSelected ? marineTheme.colors.onPrimary : marineTheme.colors.textSecondary)
          .frame(width: MarineTheme.Metrics.indicatorDotSize, height: MarineTheme.Metrics.indicatorDotSize)
        Text(title)
          .marineFont(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
      .foregroundStyle(isSelected ? marineTheme.colors.onPrimary : marineTheme.colors.textPrimary)
      .background(
        isSelected ? marineTheme.colors.primary : marineTheme.colors.surfaceBackground,
        in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
  }
  
  // MARK: - Action Views
  
  @ViewBuilder
  private var actionsView: some View {
    if let waypointID = calloutViewModel.targetWaypointID {
      waypointActionsView(waypointID: waypointID)
    } else {
      emptyTargetActionsView
    }
  }
  
  @ViewBuilder
  private func waypointActionsView(waypointID: String) -> some View {
    let isSelected = chartViewModel.goToWaypointID == waypointID
    
    VStack(spacing: MarineTheme.Spacing.small) {
      // 1. Primary Action Button (Prominent)
      Button {
        Task { @MainActor [weak waypointService = waypointService, weak calloutViewModel = calloutViewModel] in
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
        Label(
          isSelected ? "Deselect" : "Select",
          marineIcon: isSelected ? .deselect : .select
        )
        .padding(.horizontal, MarineTheme.Spacing.small)
        .lineLimit(1)
      }
      .buttonStyle(MarineButtonStyle(isSelected ? .cancel : .primary))
      
      // 2. Secondary Actions Row (Horizontal side-by-side)
      HStack(spacing: MarineTheme.Spacing.small) {
        Button {
          Task { @MainActor [weak panelManager = panelManager, weak calloutViewModel = calloutViewModel] in
            guard let panelManager, let calloutViewModel else { return }
            Logger.navigation.info("Opening waypoint detail for ID: \(waypointID, privacy: .public)")
            panelManager.commandPath = [.waypoints, .waypointDetail(waypointID)]
            panelManager.openPanel(.command)
            calloutViewModel.dismiss()
          }
        } label: {
          Label("Show Details", marineIcon: .details)
            .padding(.horizontal, MarineTheme.Spacing.small)
            .lineLimit(1)
            .minimumScaleFactor(MarineTheme.Metrics.actionTextScaleFactor)
        }
        .buttonStyle(MarineButtonStyle(.secondary))
        
        Button {
          guard let targetCoord = calloutViewModel.targetCoordinate else { return }
          Logger.navigation.info("Activating measure tool from waypoint callout")
          calloutViewModel.dismiss()
          chartViewModel.startMeasuring(from: targetCoord)
        } label: {
          Label("Measure Distance…", marineIcon: .ruler)
            .padding(.horizontal, MarineTheme.Spacing.small)
            .lineLimit(1)
            .minimumScaleFactor(MarineTheme.Metrics.actionTextScaleFactor)
        }
        .buttonStyle(MarineButtonStyle(.secondary))
      }
    }
  }
  
  @ViewBuilder
  private var emptyTargetActionsView: some View {
    VStack(spacing: MarineTheme.Spacing.small) {
      // 1. Primary Action Button (Prominent)
      Button {
        guard let targetCoord = calloutViewModel.targetCoordinate else { return }
        Task { @MainActor [weak waypointService = waypointService, weak appViewModel = appViewModel, weak calloutViewModel = calloutViewModel] in
          guard let waypointService, let appViewModel, let calloutViewModel else { return }
          let defaultName = await waypointService.generateDefaultName()
          Logger.navigation.info("Initiating waypoint creation draft from map target")
          let draftCoord = CoordinateWrapper(coordinate: targetCoord, defaultName: defaultName)
          calloutViewModel.dismiss()
          appViewModel.waypointDraft = draftCoord
        }
      } label: {
        Label("Create Waypoint…", marineIcon: .waypoint)
          .padding(.horizontal, MarineTheme.Spacing.small)
          .lineLimit(1)
      }
      .buttonStyle(MarineButtonStyle(.primary))
      
      // 2. Secondary Actions Row
      let hasActiveTarget = chartViewModel.goToWaypointID != nil
      HStack(spacing: MarineTheme.Spacing.small) {
        Button {
          Logger.navigation.info("Opening point info sheet from map target callout")
          calloutViewModel.presentPointInfo()
        } label: {
          Label("Information", marineIcon: .details)
            .padding(.horizontal, MarineTheme.Spacing.small)
            .lineLimit(1)
            .minimumScaleFactor(MarineTheme.Metrics.actionTextScaleFactor)
        }
        .buttonStyle(MarineButtonStyle(.secondary))

        Button {
          guard let targetCoord = calloutViewModel.targetCoordinate else { return }
          Logger.navigation.info("Activating measure tool from map target callout")
          calloutViewModel.dismiss()
          chartViewModel.startMeasuring(from: targetCoord)
        } label: {
          Label("Measure Distance…", marineIcon: .ruler)
            .padding(.horizontal, MarineTheme.Spacing.small)
            .lineLimit(1)
            .minimumScaleFactor(MarineTheme.Metrics.actionTextScaleFactor)
        }
        .buttonStyle(MarineButtonStyle(.secondary))
      }
      
      if hasActiveTarget {
        Button {
          Task { @MainActor [weak waypointService = waypointService, weak calloutViewModel = calloutViewModel] in
            guard let waypointService, let calloutViewModel else { return }
            Logger.navigation.info("Deselecting active target from map callout")
            waypointService.setDestination(waypointID: nil)
            calloutViewModel.dismiss()
          }
        } label: {
          Label("Deselect Target", marineIcon: .deselect)
            .padding(.horizontal, MarineTheme.Spacing.small)
            .lineLimit(1)
            .minimumScaleFactor(MarineTheme.Metrics.actionTextScaleFactor)
        }
        .buttonStyle(MarineButtonStyle(.cancel))
      }
    }
  }
}
