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

            // Conditional display of the map (if the style JSON was successfully generated)
            if mapViewModel.styleURL != nil {
                MapLibreView(
                    centerCoordinate: $mapViewModel.centerCoordinate,
                    zoomLevel: $mapViewModel.zoomLevel,
                    styleURL: $mapViewModel.styleURL,
                    mapBounds: $mapViewModel.mapBounds
                )
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

            // Display of the current center position (e.g., marine reticle)
            VStack {
                Spacer()
                Text("Lat: \(mapViewModel.centerCoordinate.latitude, specifier: "%.4f"), Lon: \(mapViewModel.centerCoordinate.longitude, specifier: "%.4f")")
                    .font(.caption)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.bottom, 30) // Clears the bottom safe area (for iPhones with Home Indicator)
            }
        }
    }
}

#Preview {
    ContentView()
}
