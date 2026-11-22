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
  @State private var selectedDetent: PresentationDetent = .height(220)
  
  private var activeDetents: Set<PresentationDetent> {
    if calloutViewModel.isPointInfoPresented {
      return [.height(measuredHeight), .medium, .large]
    } else {
      return [.height(measuredHeight)]
    }
  }

  private var backgroundInteractionDetent: PresentationDetent {
    calloutViewModel.isPointInfoPresented ? .medium : .height(measuredHeight)
  }
  
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
  }

  private func updateMeasuredHeight(_ newHeight: CGFloat) {
    guard newHeight > 0 else { return }
    let shouldAnimate = hasMeasuredInitialHeight
    hasMeasuredInitialHeight = true
    guard abs(measuredHeight - newHeight) > 1.0 else { return }
    if shouldAnimate {
      withAnimation(.snappy(duration: 0.25)) {
        measuredHeight = newHeight
        if !calloutViewModel.isPointInfoPresented {
          selectedDetent = .height(newHeight)
        }
      }
    } else {
      measuredHeight = newHeight
      if !calloutViewModel.isPointInfoPresented {
        selectedDetent = .height(newHeight)
      }
    }
    notifySheetHeightChanged(newHeight)
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.clear
          .allowsHitTesting(false)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Isolated subview so 120Hz magnetic reticle offset updates never re-evaluate MapCalloutView.body.
        CalloutReticleOverlayView(
          calloutViewModel: calloutViewModel,
          measureToolViewModel: chartViewModel.measureToolViewModel,
          containerSize: proxy.size
        )
      }
    }
    .sheet(isPresented: isSheetPresented) {
      calloutSheetContent
        .presentationDetents(activeDetents, selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationBackground(marineTheme.colors.panelBackground)
        .presentationBackgroundInteraction(.enabled(upThrough: backgroundInteractionDetent))
        .interactiveDismissDisabled(true)
        .onChange(of: calloutViewModel.isPointInfoPresented) { _, isPresented in
          if !isPresented {
            calloutViewModel.dismissPointInfo()
            withAnimation(.snappy(duration: 0.25)) {
              selectedDetent = .height(measuredHeight)
              notifySheetHeightChanged(measuredHeight)
            }
          }
        }
    }
  }
  
  // MARK: - Callout Sheet Content
  
  @ViewBuilder
  private var calloutSheetContent: some View {
    NavigationStack {
      if chartViewModel.measureToolViewModel.isActive {
        measuredRootContainer {
          measureSheetContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(marineTheme.colors.panelBackground)
        .navigationTitle("Measure Distance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbar {
          ToolbarItem(placement: .principal) {
            navigationPrincipalView(
              title: Text("Measure Distance"),
              subtitle: Text("Drag pins or long press chart to reposition")
            )
          }
          ToolbarItem(placement: .topBarTrailing) {
            MarineCloseButton {
              chartViewModel.measureToolViewModel.stop()
            }
          }
        }
      } else {
        measuredRootContainer {
          standardCalloutSheetContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(marineTheme.colors.panelBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbar {
          // Symmetric invisible leading spacer matching the close button's visual width so
          // UINavigationBar keeps wide GPS coordinates centered without shrinking them in Glove Mode.
          if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) {
              leadingBalanceSpacer
            }
            .sharedBackgroundVisibility(.hidden)
          } else {
            ToolbarItem(placement: .topBarLeading) {
              leadingBalanceSpacer
            }
          }

          // Always mount the principal ToolbarItem so UIKit never tears down/recreates titleView
          // when switching between a snapped waypoint and open-water coordinates, keeping the title centered.
          ToolbarItem(placement: .principal) {
            if let waypointID = calloutViewModel.targetWaypointID,
               let waypoint = waypointService.currentWaypoints.first(where: { $0.id == waypointID }) {
              navigationPrincipalView(
                title: Text(waypoint.name),
                subtitle: Text(waypoint.coordinate.formatted(.marineCoordinate))
              )
            } else {
              navigationPrincipalView(
                title: Text(verbatim: calloutViewModel.formattedCoordinate ?? "---")
              )
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            MarineCloseButton {
              calloutViewModel.dismiss()
            }
          }
        }
        .navigationDestination(isPresented: $calloutViewModel.isPointInfoPresented) {
          PointInformationDestinationView(calloutViewModel: calloutViewModel)
        }
      }
    }
    .containerBackground(marineTheme.colors.panelBackground, for: .navigation)
    .onAppear {
      notifySheetHeightChanged(measuredHeight)
    }
    .onDisappear {
      hasMeasuredInitialHeight = false
      selectedDetent = .height(measuredHeight)
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
      proxy.size.height + proxy.safeAreaInsets.top
    } action: { newHeight in
      updateMeasuredHeight(newHeight)
    }
  }
  
  // MARK: - Standard Callout Content
  
  @ViewBuilder
  private var standardCalloutSheetContent: some View {
    // 1. Telemetry Section (BTW & RNG)
    let vesselCoord = chartViewModel.currentCoordinate
    let bearing = calloutViewModel.bearing(from: vesselCoord)
    let distance = calloutViewModel.distance(from: vesselCoord)
    
    standardTelemetryBar(bearing: bearing, distance: distance)
    
    // 2. Contextual Action Buttons
    actionsView
  }
  
  // MARK: - Navigation Bar Items

  private var leadingBalanceSpacer: some View {
    Color.clear
      .frame(width: marineTheme.metrics.closeButtonCircleSize, height: 1)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private func navigationPrincipalView(title: Text, subtitle: Text? = nil) -> some View {
    VStack(spacing: MarineTheme.Spacing.tiny / 2) {
      title
        .monospacedDigit()
        .marineFont(.headline)
        .foregroundColor(marineTheme.colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
        .transaction { $0.animation = nil }

      if let subtitle {
        subtitle
          .monospacedDigit()
          .marineFont(.caption)
          .foregroundColor(marineTheme.colors.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
          .transaction { $0.animation = nil }
      }
    }
  }


  // MARK: - Measure Tool Content
  
  @ViewBuilder
  private var measureSheetContent: some View {
    let measureVM = chartViewModel.measureToolViewModel
    
    // 1. Telemetry Section: BRG, RECIPROCAL, RNG
    measureTelemetryBar(
      bearing: measureVM.bearing,
      reciprocal: measureVM.reciprocalBearing,
      distance: measureVM.distance
    )
    
    // 2. Contextual Actions: Active Pin Selection (Pin A / Pin B)
    HStack(spacing: MarineTheme.Spacing.small) {
      measurePinButton(title: "Pin A", pin: .start, viewModel: measureVM)
      measurePinButton(title: "Pin B", pin: .end, viewModel: measureVM)
    }
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

// MARK: - Isolated Reticle Overlay

/// Lightweight overlay that exclusively observes `reticleVisualOffset` so 120Hz magnetic pull
/// updates during chart panning do not invalidate `MapCalloutView.body` or its sheet hierarchy.
private struct CalloutReticleOverlayView: View {
  @Environment(\.marineTheme) private var marineTheme

  let calloutViewModel: MapCalloutViewModel
  let measureToolViewModel: MeasureToolViewModel
  let containerSize: CGSize

  var body: some View {
    // Kept permanently mounted in the view hierarchy so its CALayer and shadow buffer are pre-warmed,
    // guaranteeing a 0-frame opacity toggle in the exact same CATransaction as MapLibre layer hiding.
    let isSwiftUICrosshairVisible =
      calloutViewModel.isCalloutVisible &&
      !calloutViewModel.isCentering &&
      calloutViewModel.aimingCoordinate == nil &&
      !measureToolViewModel.isActive

    MarineCrosshairView.targetAiming(theme: marineTheme)
      .position(
        x: containerSize.width / 2.0 + calloutViewModel.reticleVisualOffset.width,
        y: containerSize.height * AppConstants.Map.aimingCrosshairYFraction + calloutViewModel.reticleVisualOffset.height
      )
      .opacity(isSwiftUICrosshairVisible ? 1.0 : 0.0)
      .transaction { $0.disablesAnimations = true }
      .allowsHitTesting(false)
  }
}

// MARK: - Point Information Destination

struct PointInformationDestinationView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Bindable var calloutViewModel: MapCalloutViewModel

  var body: some View {
    ScrollView {
      VStack(spacing: MarineTheme.Spacing.medium) {
        if let targetCoord = calloutViewModel.targetCoordinate {
          PointInfoGPSSection(coordinate: targetCoord)
          PointInfoMagneticDeclinationSection(
            declination: calloutViewModel.magneticDeclination,
            footerText: calloutViewModel.magneticDeclinationFooterText,
            isLoading: calloutViewModel.isPointInfoLoading
          )
          PointInfoEphemerisSection(
            ephemeris: calloutViewModel.sunEphemeris,
            isLoading: calloutViewModel.isPointInfoLoading
          )
        }
      }
      .padding(.horizontal, MarineTheme.Spacing.medium)
      .padding(.top, MarineTheme.Spacing.small)
      .padding(.bottom, MarineTheme.Spacing.medium)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(marineTheme.colors.panelBackground)
    .navigationTitle("Point Information")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        MarineCloseButton {
          calloutViewModel.dismiss()
        }
      }
    }
  }
}

// MARK: - Point Information Subviews

private struct PointInfoGPSSection: View {
  @Environment(\.marineTheme) private var marineTheme
  let coordinate: CLLocationCoordinate2D

  @State private var isCopied: Bool = false
  @State private var copyActionCount: Int = 0

  var body: some View {
    let formattedText = coordinate.formatted(.marineCoordinate)

    VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny) {
      Text("GPS POSITION")
        .marineSectionHeader()
        .padding(.leading, MarineTheme.Spacing.small)

      HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
        Text(verbatim: formattedText)
          .monospacedDigit()
          .marineFont(.body)
          .foregroundColor(marineTheme.colors.textPrimary)
          .lineLimit(2)
          .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
          .transaction { $0.animation = nil }

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
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
}

private struct PointInfoMagneticDeclinationSection: View {
  @Environment(\.marineTheme) private var marineTheme
  let declination: Measurement<UnitAngle>?
  let footerText: String?
  let isLoading: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny) {
      Text("MAGNETIC DECLINATION")
        .marineSectionHeader()
        .padding(.leading, MarineTheme.Spacing.small)

      HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
        Text("Variation")
          .marineFont(.body)
          .foregroundColor(marineTheme.colors.textSecondary)

        Spacer(minLength: MarineTheme.Spacing.small)

        if let declination {
          Text(verbatim: declination.marineDeclinationFormatted)
            .monospacedDigit()
            .marineFont(.body)
            .foregroundColor(marineTheme.colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
            .transaction { $0.animation = nil }
        } else if isLoading {
          Text(verbatim: "1.5° W")
            .monospacedDigit()
            .marineFont(.body)
            .redacted(reason: .placeholder)
        } else {
          Text(verbatim: "---")
            .monospacedDigit()
            .marineFont(.body)
            .foregroundColor(marineTheme.colors.textSecondary)
        }
      }
      .padding(.horizontal, MarineTheme.Spacing.small)
      .padding(.vertical, MarineTheme.Spacing.medium)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        marineTheme.colors.surfaceBackground,
        in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
      )

      if let footerText {
        Text(verbatim: footerText)
          .marineFont(.footnote)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .padding(.horizontal, MarineTheme.Spacing.small)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct PointInfoEphemerisSection: View {
  @Environment(\.marineTheme) private var marineTheme
  let ephemeris: SunEphemeris?
  let isLoading: Bool

  var body: some View {
    let referenceDate = ephemeris?.referenceDate ?? Date()
    let displayTimeZone = ephemeris?.timeZone ?? .current
    let headerFormat = Date.FormatStyle(timeZone: displayTimeZone).weekday(.abbreviated).day().month(.abbreviated)
    let dateString = referenceDate.formatted(headerFormat).uppercased()
    let displayRows = SunEphemerisDisplayRow.rows(for: ephemeris)
    let footerText = SunEphemerisDisplayRow.footerText(for: ephemeris)

    VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny) {
      Text("SOLAR EPHEMERIS - \(dateString)")
        .marineSectionHeader()
        .padding(.leading, MarineTheme.Spacing.small)

      // Always render all 4 ephemeris rows (using "---" when unavailable) to keep layout and scanning predictable.
      VStack(spacing: 0) {
        ForEach(Array(displayRows.enumerated()), id: \.element.id) { index, row in
          if index > 0 {
            Divider()
              .padding(.leading, separatorLeadingInset)
          }

          ephemerisRow(row)
        }
      }
      .background(
        marineTheme.colors.surfaceBackground,
        in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
      )

      if let footerText {
        Text(verbatim: footerText)
          .marineFont(.footnote)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .padding(.horizontal, MarineTheme.Spacing.small)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var separatorLeadingInset: CGFloat {
    MarineTheme.Spacing.small * 2 + MarineTheme.Spacing.large
  }

  @ViewBuilder
  private func ephemerisRow(_ row: SunEphemerisDisplayRow) -> some View {
    HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
      Image(systemName: row.icon)
        .marineFont(.body)
        .foregroundColor(marineTheme.colors.textSecondary)
        .frame(width: MarineTheme.Spacing.large)

      Text(row.title)
        .marineFont(.body)
        .foregroundColor(marineTheme.colors.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)

      Spacer(minLength: MarineTheme.Spacing.small)

      ephemerisValueView(row.value)
    }
    .padding(.horizontal, MarineTheme.Spacing.small)
    .padding(.vertical, MarineTheme.Spacing.medium)
  }

  @ViewBuilder
  private func ephemerisValueView(_ value: SunEphemerisRowValue) -> some View {
    switch value {
    case let .time(date, referenceDate, timeZone):
      Text(verbatim: date.marineEphemerisTimeFormatted(relativeTo: referenceDate, timeZone: timeZone))
        .monospacedDigit()
        .marineFont(.body)
        .foregroundColor(marineTheme.colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(MarineTheme.Metrics.compactTextScaleFactor)
        .transaction { $0.animation = nil }
    case .unavailable:
      Text(verbatim: "---")
        .marineFont(.body)
        .foregroundStyle(marineTheme.colors.textSecondary)
        .transaction { $0.animation = nil }
    case .missing:
      if isLoading {
        let tzAbbr = TimeZone.current.abbreviation() ?? "UTC"
        Text(verbatim: "06:00 \(tzAbbr)")
          .monospacedDigit()
          .marineFont(.body)
          .redacted(reason: .placeholder)
      } else {
        Text(verbatim: "---")
          .monospacedDigit()
          .marineFont(.body)
          .foregroundColor(marineTheme.colors.textSecondary)
      }
    }
  }
}
