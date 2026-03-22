//
//  ContentView.swift
//  Sillage
//
//  Created by Alcyone on 19/03/2026.
//

import SwiftUI
import CoreLocation

struct ContentView: View {

    // Instantiation of our ViewModel
    @StateObject private var mapViewModel = MapViewModel()

    var body: some View {
        // ZStack so the map occupies the entire space (ignoring safe areas)
        ZStack {

            // Conditional display of the map (if the active map path was successfully found)
            if mapViewModel.activeMapPath != nil {
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

                // Bottom-right Floating Action Button
                HStack {
                    Spacer()
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
}
