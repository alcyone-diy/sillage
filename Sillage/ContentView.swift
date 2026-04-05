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

  @EnvironmentObject var mapViewModel: MapViewModel

  // State for showing the settings sheet
  @State private var isShowingSettings = false

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
        Text("Loading marine charts...")
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
          // Settings Button
          Button(action: {
            isShowingSettings = true
          }) {
            Image(systemName: "gearshape.fill")
              .font(.system(size: 24, weight: .bold))
              .foregroundColor(.white)
              .frame(width: 60, height: 60)
              .background(Color.blue)
              .clipShape(Circle())
              .shadow(radius: 5)
          }
          .padding()
          .padding(.bottom, 30) // Clears bottom safe area

          Spacer()

          // Recenter Button
          Button(action: {
            mapViewModel.activateTracking()
          }) {
            Image(systemName: mapViewModel.isTrackingUser ? "location.fill" : "location")
              .font(.system(size: 24, weight: .bold))
              .foregroundColor(.white)
              .frame(width: 60, height: 60)
              .background(mapViewModel.isTrackingUser ? Color.blue : Color.gray)
              .clipShape(Circle())
              .shadow(radius: 5)
          }
          .padding()
          .padding(.bottom, 30) // Clears bottom safe area
      }
    }
    }
    .sheet(isPresented: $isShowingSettings) {
      SettingsView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
  }

  // Marine Dashboard View
  private var marineDashboard: some View {
      VStack(spacing: 8) {
        Text(mapViewModel.formattedCoordinates)
          .font(.headline)
          .foregroundColor(.yellow)

        HStack(spacing: 40) {
          VStack {
            Text("SOG")
              .font(.caption)
              .foregroundColor(.gray)
            Text(String(format: "%.1f kts", mapViewModel.speedOverGround))
              .font(.title3.bold())
              .foregroundColor(.white)
          }

          VStack {
            Text("COG")
              .font(.caption)
              .foregroundColor(.gray)
            Text(String(format: "%.0f°", mapViewModel.courseOverGround))
              .font(.title3.bold())
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
    .environmentObject(MapViewModel())
}
