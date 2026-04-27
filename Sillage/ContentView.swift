//
//  ContentView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//
//  Created by Alcyone on 19/03/2026.
//

import SwiftUI
import CoreLocation

struct ContentView: View {

  @Environment(AppViewModel.self) private var appViewModel
  @Environment(MapViewModel.self) var mapViewModel
  @Environment(CommandPanelViewModel.self) private var commandPanelViewModel
  @Environment(\.verticalSizeClass) var verticalSizeClass
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    // ZStack so the map occupies the entire space (ignoring safe areas)
    ZStack {

      // Conditional display of the map (if the current map source was successfully found)
      if mapViewModel.currentMapSource != nil {
        MapLibreView(viewModel: mapViewModel)
          .ignoresSafeArea() // Essential for full-screen immersion

      } else {
        // Fallback view if MBTiles data cannot be loaded
        VStack {
          ProgressView()
            .padding()
          Text("Loading marine charts…")
            .foregroundColor(.secondary)
        }
      }

      // UI Overlay
      VStack {
        // Top Marine Dashboard
        marineDashboard

        Spacer()

        // Bottom Floating Action Buttons
        HStack {
            // Command Panel Button
            CommandButtonView()
              .padding()
              .padding(.bottom, 30) // Clears bottom safe area

            Spacer()

            // Recenter Button
            Button(action: {
              mapViewModel.toggleTrackingMode()
            }) {
              Image(systemName: trackingIconName(for: mapViewModel.trackingMode))
                .marineFont(.title3)
                .foregroundColor(.white)
            }
            .buttonStyle(MarineFABStyle(backgroundColor: trackingBackgroundColor(for: mapViewModel.trackingMode)))
            .padding()
            .padding(.bottom, 30) // Clears bottom safe area
        }
      }

      // Permanent Overlay Layer
      ZStack {
        if commandPanelViewModel.isPanelOpen {
          // Dimming Background
          Color.black.opacity(0.3)
            .ignoresSafeArea()
            .onTapGesture {
              withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                commandPanelViewModel.isPanelOpen = false
              }
            }
            .transition(.opacity)
            .zIndex(0)
        }

        // Drawer
        Group {
          if verticalSizeClass == .compact {
            // Landscape (Trailing Drawer)
            HStack(spacing: 0) {
              Spacer(minLength: 0)
              CommandPanelView()
                .frame(width: marineTheme.commandPanelWidth)
                .clipShape(
                  UnevenRoundedRectangle(
                    topLeadingRadius: marineTheme.drawerCornerRadius,
                    bottomLeadingRadius: marineTheme.drawerCornerRadius,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                  )
                )
            }
            .ignoresSafeArea(.all)
            .offset(x: commandPanelViewModel.isPanelOpen ? 0 : marineTheme.commandPanelWidth + 200)
          } else {
            // Portrait (Bottom Drawer)
            VStack(spacing: 0) {
              Spacer(minLength: 0)
              CommandPanelView()
                .containerRelativeFrame(.vertical, alignment: .bottom) { length, _ in
                  length * marineTheme.commandPanelPortraitHeightFraction
                }
                .clipShape(
                  UnevenRoundedRectangle(
                    topLeadingRadius: marineTheme.drawerCornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: marineTheme.drawerCornerRadius,
                    style: .continuous
                  )
                )
            }
            .ignoresSafeArea(.all)
            .offset(y: commandPanelViewModel.isPanelOpen ? 0 : 1500)
          }
        }
        .zIndex(1) // Critical for keeping the drawer above the fading background during dismissal
      }
    }
    .alert(
      isPresented: Bindable(appViewModel).showImportError,
      error: appViewModel.importError
    ) { _ in
      Button("OK", role: .cancel) { }
    } message: { error in
      Text(error.localizedDescription)
    }
  }

  private func trackingIconName(for mode: MapTrackingMode) -> String {
    switch mode {
    case .free: return "location"
    case .northUp: return "location.fill"
    case .courseUp: return "location.north.line.fill"
    }
  }

  private func trackingBackgroundColor(for mode: MapTrackingMode) -> Color {
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
        if let coordinate = mapViewModel.currentCoordinate {
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
              if let sogMeasurement = mapViewModel.speedOverGround {
                let sogKnots = sogMeasurement.converted(to: .knots).value
                Text("\(sogKnots.formatted(.number.precision(.fractionLength(1)))) kts")
              } else {
                Text("-- kts")
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
              if let cog = mapViewModel.courseOverGround {
                Text("\(cog.converted(to: .degrees).value.formatted(.number.precision(.fractionLength(0))))°")
              } else {
                Text("--°")
              }
            }
              .marineFont(.instrumentData)
              .foregroundColor(.white)
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

#Preview {
  ContentView()
    .environment(MapViewModel())
}
