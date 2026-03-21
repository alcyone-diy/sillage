//
//  ContentView.swift
//  Sillage
//
//  Created by Alcyone on 19/03/2026.
//

import SwiftUI

struct ContentView: View {

    // Instanciation de notre ViewModel
    @StateObject private var mapViewModel = MapViewModel()

    var body: some View {
        // ZStack pour que la carte occupe tout l'espace (ignorant la zone sécurisée)
        ZStack {

            // Affichage conditionnel de la carte (si le style JSON a bien été généré)
            if mapViewModel.styleURL != nil {
                MapLibreView(
                    centerCoordinate: $mapViewModel.centerCoordinate,
                    zoomLevel: $mapViewModel.zoomLevel,
                    styleURL: $mapViewModel.styleURL
                )
                .ignoresSafeArea() // Indispensable pour l'immersion en plein écran

            } else {
                // Vue de secours si les données MBTiles ne peuvent pas être chargées
                VStack {
                    ProgressView()
                        .padding()
                    Text("Chargement des cartes marines...")
                        .foregroundColor(.secondary)
                }
            }

            // Affichage de la position au centre de l'écran (réticule marin par ex)
            VStack {
                Spacer()
                Text("Lat: \(mapViewModel.centerCoordinate.latitude, specifier: "%.4f"), Lon: \(mapViewModel.centerCoordinate.longitude, specifier: "%.4f")")
                    .font(.caption)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.bottom, 30) // Pour dégager la "safe area" du bas (si iPhone avec Home Indicator)
            }
        }
    }
}

#Preview {
    ContentView()
}
