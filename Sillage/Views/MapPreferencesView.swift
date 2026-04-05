//
//  MapPreferencesView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct MapPreferencesView: View {
  @EnvironmentObject var mapViewModel: MapViewModel

  // A helper enum to easily toggle between the two specific sources
  private enum MapSourceSelection {
    case local
    case remote
  }

  private var currentSelection: MapSourceSelection {
    switch mapViewModel.currentMapSource {
    case .localMBTiles:
      return .local
    case .remoteGeoGarage:
      return .remote
    case .none:
      return .local // Default fallback
    }
  }

  var body: some View {
    Form {
      Section(header: Text("Map Source").font(.headline)) {

        // Local MBTiles Button
        Button(action: {
          if let url = Bundle.main.url(forResource: "7413_pal300", withExtension: "mbtiles") {
            mapViewModel.switchMapSource(to: .localMBTiles(url: url))
          }
        }) {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("Local MBTiles")
                .font(.title3.bold())
                .foregroundColor(.primary)
              Text("Offline marine charts")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            Spacer()
            if currentSelection == .local {
              Image(systemName: "checkmark")
                .foregroundColor(.blue)
                .font(.title2.weight(.bold))
            }
          }
          // Enforce Marine UI large touch targets
          .frame(minHeight: 60)
          .contentShape(Rectangle()) // Make the entire row tappable
        }
        .buttonStyle(.plain) // Prevent form default button styling

        // Remote GeoGarage Button
        Button(action: {
          mapViewModel.switchMapSource(to: .remoteGeoGarage(clientID: Secrets.geoGarageClientID, layerID: Secrets.geoGarageLayerID))
        }) {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("Remote GeoGarage")
                .font(.title3.bold())
                .foregroundColor(.primary)
              Text("Online marine charts")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            Spacer()
            if currentSelection == .remote {
              Image(systemName: "checkmark")
                .foregroundColor(.blue)
                .font(.title2.weight(.bold))
            }
          }
          // Enforce Marine UI large touch targets
          .frame(minHeight: 60)
          .contentShape(Rectangle()) // Make the entire row tappable
        }
        .buttonStyle(.plain)

      }
    }
    .navigationTitle("Map Preferences")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    MapPreferencesView()
      .environmentObject(MapViewModel())
  }
}
