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

                // Map Source Switcher
                mapSourceSwitcher

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

    // Map Source Switcher View
    private var mapSourceSwitcher: some View {
        HStack {
            Spacer()
            Menu {
                Button("Local MBTiles") {
                    if let url = Bundle.main.url(forResource: "7413_pal300", withExtension: "mbtiles") {
                        mapViewModel.switchMapSource(to: .localMBTiles(url: url))
                    }
                }
                Button("Remote GeoGarage") {
                    mapViewModel.switchMapSource(to: .remoteGeoGarage(clientID: "test_client", layerID: "test_layer"))
                }
            } label: {
                Image(systemName: "map")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }
            .padding(.trailing, 20)
        }
        .padding(.top, 10)
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
