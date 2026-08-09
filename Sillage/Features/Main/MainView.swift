//
//  ContentView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-03-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation

struct ContentView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(AppViewModel.self) private var appViewModel
  @Environment(ChartViewModel.self) var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManagerViewModel
  @Environment(TrackRecordingService.self) private var trackRecordingService
  @Environment(\.waypointService) private var waypointService
  @Environment(AnchorViewModel.self) private var anchorViewModel
  @Environment(PermissionService.self) private var permissionService
  @Environment(ActiveTrackViewModel.self) private var activeTrackViewModel
  @Environment(\.marineTheme) private var marineTheme

  @State private var localSheetPresented: Bool = false
  @State private var permissionGateType: PermissionGateType? = nil

  var body: some View {
    GeometryReader { geo in
      let isPortrait = geo.size.height > geo.size.width
      let isPhone = horizontalSizeClass == .compact || verticalSizeClass == .compact
      // Only use the native sheet if it's a Phone AND it's physically in portrait orientation.
      let useNativeSheet = isPhone && isPortrait

      // ZStack so the map occupies the entire space (ignoring safe areas)
      ZStack {

        // Conditional display of the map (if the current map source was successfully found)
        if chartViewModel.currentChartSource != nil {
          MapLibreView(viewModel: chartViewModel)
            .ignoresSafeArea() // Essential for full-screen immersion
            .simultaneousGesture(
              TapGesture().onEnded {
                if panelManagerViewModel.activePanel != .none {
                  panelManagerViewModel.closePanel()
                }
              }
            )

        } else {
          // Fallback view if MBTiles data cannot be loaded
          VStack {
            ProgressView()
              .padding()
            Text("Loading marine charts…")
              .foregroundColor(.secondary)
          }
        }
        
        MapCalloutOverlayView(
          calloutViewModel: chartViewModel.calloutViewModel,
          chartViewModel: chartViewModel
        )
        .ignoresSafeArea()
        .onChange(of: panelManagerViewModel.activePanel) { _, newPanel in
          if newPanel != .none {
            chartViewModel.calloutViewModel.dismiss()
          }
        }

        OfflineSelectionOverlayView()

        if anchorViewModel.isAdjustingAnchor {
          AnchorAdjustOverlayView()
            .transition(.opacity)
        } else if anchorViewModel.isPreparingDropAnchor {
          AnchorDropOverlayView()
            .transition(.opacity)
        }

        // UI Overlay (Focus Mode during Action Confirmation Cards: Top Dashboard & Command Panel Button hidden; Location Button remains visible elevated above the card)
        VStack {
          if !chartViewModel.isActionConfirmationCardActive {
            // Top Marine Dashboard
            marineDashboard

            if anchorViewModel.status == .dragging && anchorViewModel.isAlertSilenced {
              AnchoringStatusCapsuleView(anchorViewModel: anchorViewModel) {
                panelManagerViewModel.openAnchorAlarmPanel()
              }
              .padding(.horizontal)
              .transition(.move(edge: .top).combined(with: .opacity))
            }
          }

          Spacer()

          // Bottom Floating Action Buttons
          HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 16) {
              MapScaleView(mapScale: chartViewModel.mapScale, zoomLevel: chartViewModel.zoomLevel)
                .padding(.leading, 8)

              // Location / Recenter Button (ALWAYS DISPLAYED)
              Button(action: {
                if let gate = panelManagerViewModel.executeOrRequestPermission(
                    type: .location(trigger: .mapTracking),
                    in: permissionService,
                    action: { [weak chartViewModel] in
                        chartViewModel?.toggleTrackingMode()
                    }
                ) {
                    permissionGateType = gate
                }
              }) {
                Image(marineIcon: trackingIconName(for: chartViewModel.trackingMode))
                  .marineFont(.title3)
                  .foregroundColor(.white)
              }
              .buttonStyle(MarineFABStyle(backgroundColor: trackingBackgroundColor(for: chartViewModel.trackingMode)))
              .padding()
              .padding(.bottom, locationButtonBottomPadding)
              .animation(.easeInOut(duration: 0.25), value: chartViewModel.isActionConfirmationCardActive)
            }

            Spacer()

            if !chartViewModel.isActionConfirmationCardActive {
              // Command Panel Button (NEVER DISPLAYED when an action confirmation card is active)
              CommandButtonView()
                .padding()
                .padding(.bottom, MarineTheme.Spacing.fabBottomDefault)
            }
          }
        }



        // 2. Custom Drawers (For iPad and iPhone Landscape)
        if !useNativeSheet && panelManagerViewModel.activePanel != .none {
          if isPortrait {
            // iPad Portrait: Custom Bottom Drawer
            VStack(spacing: 0) {
              Spacer()
              panelView
                  .background(Material.thickMaterial)
                  .frame(height: geo.size.height * 0.40)
                  .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                  .ignoresSafeArea(.all, edges: .bottom)
            }
            .transition(.move(edge: .bottom))
            .zIndex(1)
          } else {
            // Landscape (iPhone & iPad): Custom Trailing Drawer
            HStack(spacing: 0) {
                Spacer()
                panelView
                    .background(Material.thickMaterial)
                    // Use 33% of screen width for the side drawer
                    .containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: 0)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20))
                    .ignoresSafeArea(.all, edges: [.top, .bottom, .trailing])
            }
            .transition(.move(edge: .trailing))
            .zIndex(1)
          }
        }
      }
      .environment(\.physicalSafeArea, geo.safeAreaInsets)
      .onChange(of: panelManagerViewModel.activePanel, initial: true) { _, newPanel in
        if useNativeSheet { localSheetPresented = (newPanel != .none) }
      }
      .onChange(of: useNativeSheet) { _, isNowSheet in
        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
          if isNowSheet {
            // Landscape -> Portrait: ZStack vanishes instantly, Native Sheet appears instantly.
            localSheetPresented = (panelManagerViewModel.activePanel != .none)
          } else {
            // Portrait -> Landscape: Native Sheet vanishes instantly, ZStack appears instantly.
            localSheetPresented = false
          }
        }
      }
      .onChange(of: localSheetPresented) { _, isPresented in
        // Only bubble up the dismissal to global state if we are STILL in Native Sheet mode.
        // This confirms it was an explicit user swipe down, not a device rotation layout shift.
        if !isPresented && useNativeSheet && panelManagerViewModel.activePanel != .none {
          panelManagerViewModel.closePanel()
        }
      }
      // 3. The Native Bottom Drawer (For iPhone Portrait ONLY)
      .sheet(isPresented: $localSheetPresented) {
        if useNativeSheet {
          panelView
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationDragIndicator(.visible)
        } else {
          // Immediately render nothing during UIKit's teardown phase to prevent center-screen flashing
          Color.clear
            .presentationBackground(.clear)
        }
      }
      } // End of Main ZStack
    .fullScreenCover(
      isPresented: Binding(
        get: { anchorViewModel.status == .dragging && !anchorViewModel.isAlertSilenced },
        set: { _ in }
      )
    ) {
      AnchorAlertView()
        .environment(anchorViewModel)
        .environment(\.marineTheme, appViewModel.marineTheme)
    }

    .onChange(of: permissionService.locationStatus) { _, status in
      if status == .authorized {
        panelManagerViewModel.finalizePendingLocationAction()
        activeTrackViewModel.finalizePendingLocationAction()
        permissionGateType = nil
        activeTrackViewModel.pendingPermissionGate = nil
      }
    }
    .onChange(of: anchorViewModel.status) { _, status in
      if status == .dragging {
        panelManagerViewModel.closePanel()
      }
    }


    .background {
      Color.clear.alert(
        isPresented: Bindable(appViewModel).showImportError,
        error: appViewModel.importError
      ) { _ in
        Button("OK", role: .cancel) { }
      } message: { error in
        Text(error.localizedDescription)
      }
    }
    .background {
      Color.clear.sheet(item: Bindable(appViewModel).waypointDraft) { item in
        if let waypointService {
          NavigationStack {
            let viewModel = WaypointDetailViewModel(
              waypointService: waypointService,
              defaultName: item.defaultName,
              initialCoordinate: item.coordinate
            )
            WaypointDetailView(
              viewModel: viewModel,
              onGoToRequested: { waypointID in
                appViewModel.waypointDraft = nil
                waypointService.setDestination(waypointID: waypointID)
                panelManagerViewModel.closePanel()
              },
              onCancelNavigationRequested: {
                appViewModel.waypointDraft = nil
                waypointService.setDestination(waypointID: nil)
              }
            )
          }
        }
      }
    }
    .background {
      Color.clear.sheet(item: $permissionGateType) { gateType in
        PermissionGateView(type: gateType)
          .presentationDetents([.medium, .large])
      }
    }
  }

  @ViewBuilder
  private var panelView: some View {
    Group {
      switch panelManagerViewModel.activePanel {
      case .command:
        CommandPanelView()
      case .none:
        EmptyView()
      }
    }
    // MARK: - Architectural Constraint
    // These specific modals MUST remain attached to `panelView` instead of the root MainView.
    // Why? In SwiftUI on iOS, if a root View presents a native `.sheet` (the Command Panel in Portrait),
    // the root UIViewController is actively presenting a modal.
    // If we then trigger a `.alert` or `.sheet` from the ROOT view, iOS (UIKit) enforces a strict rule:
    // A UIViewController can only present one modal at a time. It will forcibly dismiss the active `.sheet`
    // to present the new `.alert`.
    // By attaching these modals directly to the content of the `.sheet` (`panelView`), the alert is presented
    // BY the sheet's UIViewController, safely layering over it without dismissing the panel.
    .sheet(item: Bindable(activeTrackViewModel).pendingPermissionGate) { gateType in
      PermissionGateView(type: gateType)
        .presentationDetents([.medium, .large])
    }
    .alert(
      "Stop Track Recording",
      isPresented: Bindable(activeTrackViewModel).showStopConfirmation
    ) {
      Button("Stop", role: .destructive) {
        activeTrackViewModel.confirmStopRecording()
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("Are you sure you want to stop recording this track?")
    }
  }

  private func trackingIconName(for mode: ChartTrackingMode) -> MarineIcon {
    switch mode {
    case .free: return .trackingFree
    case .northUp: return .trackingNorthUp
    case .courseUp: return .trackingCourseUp
    }
  }

  /// Dynamically computes the bottom padding for the Location FAB to maintain exact theme spacing above active confirmation cards.
  private var locationButtonBottomPadding: CGFloat {
    if chartViewModel.isActionConfirmationCardActive && panelManagerViewModel.actionConfirmationCardHeight > 0 {
      return panelManagerViewModel.actionConfirmationCardHeight + panelManagerViewModel.actionConfirmationCardBottomPadding
    } else {
      return MarineTheme.Spacing.fabBottomDefault
    }
  }

  private func trackingBackgroundColor(for mode: ChartTrackingMode) -> Color {
    switch mode {
    case .free: return marineTheme.colors.inactive
    case .northUp, .courseUp: return marineTheme.colors.primary
    }
  }

  // Marine Dashboard View
  private var marineDashboard: some View {
    HStack(spacing: MarineTheme.Spacing.medium) {
      // SOG Telemetry
      VStack(spacing: 2) {
        Text("SOG")
          .marineFont(.instrumentLabel)
          .foregroundColor(marineTheme.colors.textSecondary)

        if let sogMeasurement = chartViewModel.smoothedSOG {
          let sogKnots = sogMeasurement.converted(to: .knots).value
          Text(
            Measurement(value: sogKnots, unit: UnitSpeed.knots).formatted(
              .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(1))
              )
            )
          )
          .marineFont(.instrumentData)
          .foregroundColor(marineTheme.colors.textPrimary)
        } else {
          Text("--")
            .marineFont(.instrumentData)
            .foregroundColor(marineTheme.colors.textSecondary)
        }
      }

      Divider()
        .frame(height: 28)

      // COG Telemetry
      VStack(spacing: 2) {
        Text("COG")
          .marineFont(.instrumentLabel)
          .foregroundColor(marineTheme.colors.textSecondary)

        if let cog = chartViewModel.smoothedCOG {
          Text("\(cog.converted(to: .degrees).value.formatted(.number.precision(.fractionLength(0))))°")
            .marineFont(.instrumentData)
            .foregroundColor(marineTheme.colors.textPrimary)
        } else {
          Text("--°")
            .marineFont(.instrumentData)
            .foregroundColor(marineTheme.colors.textSecondary)
        }
      }

      if chartViewModel.goToWaypointVisualState != nil {
        Divider()
          .frame(height: 28)

        // BTW Telemetry
        VStack(spacing: 2) {
          Text("BTW")
            .marineFont(.instrumentLabel)
            .foregroundColor(marineTheme.colors.textSecondary)

          if let btw = chartViewModel.bearingToWaypoint {
            Text("\(btw.converted(to: .degrees).value.formatted(.number.precision(.fractionLength(0))))°")
              .marineFont(.instrumentData)
              .foregroundColor(marineTheme.colors.textPrimary)
          } else {
            Text("--°")
              .marineFont(.instrumentData)
              .foregroundColor(marineTheme.colors.textSecondary)
          }
        }
      }
    }
    .padding(.horizontal, MarineTheme.Spacing.medium)
    .padding(.vertical, MarineTheme.Spacing.small + 2)
    .background(
      .regularMaterial,
      in: RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous)
        .stroke(marineTheme.colors.border.opacity(0.4), lineWidth: MarineTheme.Metrics.borderWidth / 2)
    )
    .shadow(color: Color.black.opacity(0.15), radius: MarineTheme.Metrics.shadowRadius * 3, x: 0, y: MarineTheme.Metrics.shadowOffset * 3)
    .padding(.horizontal)
    .padding(.top, 10)
  }
}

// MARK: - iOS 18 Dynamic Island Style Anchor Status Capsule
private struct AnchoringStatusCapsuleView: View {
  let anchorViewModel: AnchorViewModel
  let onManageTap: () -> Void
  @State private var isPulsing = false

  var body: some View {
    Button(action: onManageTap) {
      HStack(spacing: 12) {
        // Pulsing Red Status Indicator Dot
        ZStack {
          Circle()
            .fill(Color.red.opacity(0.35))
            .frame(width: 22, height: 22)
            .scaleEffect(isPulsing ? 1.4 : 1.0)
            .opacity(isPulsing ? 0.0 : 0.8)
          
          Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
        }

        VStack(alignment: .leading, spacing: 1) {
          Text("Anchor Dragging")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(.primary)

          if let dist = anchorViewModel.currentDistance {
            let distMeters = Int(dist.converted(to: .meters).value)
            Text("\(distMeters)m out of zone")
              .font(.system(size: 11, weight: .semibold, design: .monospaced))
              .foregroundColor(.secondary)
          }
        }

        Spacer()

        // Compact Glass Action Pill
        HStack(spacing: 5) {
          Image(systemName: "slider.horizontal.3")
            .font(.system(size: 12, weight: .bold))
          Text("Manage")
            .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.08))
        .clipShape(Capsule())
        .foregroundColor(.primary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.ultraThinMaterial)
      .clipShape(Capsule())
      .overlay(
        Capsule()
          .stroke(
            LinearGradient(
              colors: [Color.red.opacity(0.9), Color.orange.opacity(0.4)],
              startPoint: .leading,
              endPoint: .trailing
            ),
            lineWidth: 1.5
          )
      )
      .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    .onAppear {
      withAnimation(Animation.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
        isPulsing = true
      }
    }
  }
}

