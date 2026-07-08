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
        
        OfflineSelectionOverlayView()

        // UI Overlay
        VStack {
          // Top Marine Dashboard
          marineDashboard

          Spacer()

          // Bottom Floating Action Buttons
          HStack {
            // Recenter Button
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
            .padding(.bottom, 30) // Clears bottom safe area

            Spacer()

            // Command Panel Button
            CommandButtonView()
              .padding()
              .padding(.bottom, 30) // Clears bottom safe area
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
    .alert(
      isPresented: Bindable(appViewModel).showImportError,
      error: appViewModel.importError
    ) { _ in
      Button("OK", role: .cancel) { }
    } message: { error in
      Text(error.localizedDescription)
    }
    .sheet(item: $permissionGateType) { gateType in
      PermissionGateView(type: gateType)
        .presentationDetents([.medium, .large])
    }
    .onChange(of: permissionService.locationStatus) { _, status in
      if status == .authorized {
        panelManagerViewModel.finalizePendingLocationAction()
        permissionGateType = nil
      }
    }
    .sheet(item: Bindable(appViewModel).waypointDraft) { item in
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
    .fullScreenCover(
      isPresented: Binding(
        get: { anchorViewModel.status == .dragging },
        set: { _ in }
      )
    ) {
      AnchorAlertView()
        .environment(anchorViewModel)
        .environment(\.marineTheme, appViewModel.marineTheme)
    }
  }

  @ViewBuilder
  private var panelView: some View {
    switch panelManagerViewModel.activePanel {
    case .command:
      CommandPanelView()
    case .none:
      EmptyView()
    }
  }

  private func trackingIconName(for mode: ChartTrackingMode) -> MarineIcon {
    switch mode {
    case .free: return .trackingFree
    case .northUp: return .trackingNorthUp
    case .courseUp: return .trackingCourseUp
    }
  }

  private func trackingBackgroundColor(for mode: ChartTrackingMode) -> Color {
    switch mode {
    case .free: return MarineTheme.Colors.inactive
    case .northUp, .courseUp: return MarineTheme.Colors.primary
    }
  }

  // Marine Dashboard View
  private var marineDashboard: some View {
      VStack(spacing: 8) {
        // TODO: Need to find a way to add it back without taking too much space.
        /*
        if let coordinate = chartViewModel.currentCoordinate {
          Text(coordinate.formatted(.marineCoordinate))
            .marineFont(.instrumentData)
            .foregroundColor(.yellow)
        } else {
          Text("-- / --")
            .marineFont(.instrumentData)
            .foregroundColor(.yellow)
        }
        */
        HStack(spacing: 40) {
          VStack {
            Text("SOG")
              .marineFont(.instrumentLabel)
              .foregroundColor(.secondary)
            Group {
              if let sogMeasurement = chartViewModel.speedOverGround {
                let sogKnots = sogMeasurement.converted(to: .knots).value
                Text(Measurement(value: sogKnots, unit: UnitSpeed.knots).formatted(
                    .measurement(width: .abbreviated,
                                 usage: .asProvided,
                                 numberFormatStyle: .number.precision(.fractionLength(1)))))

              } else {
                Text("--")
              }
            }
              .marineFont(.instrumentData)
              .foregroundColor(.white)
          }

          VStack {
            Text("COG")
              .marineFont(.instrumentLabel)
              .foregroundColor(.secondary)
            Group {
              if let cog = chartViewModel.courseOverGround {
                Text("\(cog.converted(to: .degrees).value.formatted(.number.precision(.fractionLength(0))))°")
              } else {
                Text("--°")
              }
            }
              .marineFont(.instrumentData)
              .foregroundColor(.white)
          }
          
          if chartViewModel.goToWaypointFeature != nil {
            VStack {
              Text("BTW")
                .marineFont(.instrumentLabel)
                .foregroundColor(.secondary)
              Group {
                if let btw = chartViewModel.bearingToWaypoint {
                  Text("\(btw.converted(to: .degrees).value.formatted(.number.precision(.fractionLength(0))))°")
                } else {
                  Text("--°")
                }
              }
                .marineFont(.instrumentData)
                .foregroundColor(.white)
            }
          }
        }
      }
      .padding()
      .background(Material.ultraThinMaterial)
      .environment(\.colorScheme, .dark)
      .cornerRadius(12)
      .padding(.horizontal)
      .padding(.top, 10)
  }
}
