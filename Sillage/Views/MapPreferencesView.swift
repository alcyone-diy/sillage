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
          MapSourceRowView(
            title: "Local MBTiles",
            subtitle: "Offline marine charts",
            isSelected: currentSelection == .local
          )
          .marineListCell()
        }
        .buttonStyle(.plain) // Prevent form default button styling

      }

      Section(header: Text("Online Charts (GeoGarage)").marineFont(.headline)) {
        if mapViewModel.availableGeoGarageLayers.isEmpty {
          NavigationLink(destination: GeoGarageLoginView()) {
            Text("Login to GeoGarage")
          }
          .buttonStyle(MarineButtonStyle())
        } else {
          ForEach(mapViewModel.availableGeoGarageLayers) { layer in
            let isSelected = currentSelection == .remote && {
              if case .remoteGeoGarage(_, let currentLayerID) = mapViewModel.currentMapSource {
                return currentLayerID == layer.layer
              }
              return false
            }()

            Button(action: {
              mapViewModel.switchMapSource(to: .remoteGeoGarage(clientID: AppConfiguration.shared.geoGarageClientID, layerID: layer.layer))
            }) {
              MapSourceRowView(
                title: layer.brand_name,
                subtitle: "Valid until \(layer.valid_until)",
                isSelected: isSelected
              )
              .marineListCell()
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .navigationTitle("Map Preferences")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct MapSourceRowView: View {
  let title: String
  let subtitle: String
  let isSelected: Bool

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .marineFont(.body)
          .foregroundColor(.primary)
        Text(subtitle)
          .marineFont(.subheadline)
          .foregroundColor(.secondary)
      }
      Spacer()
      if isSelected {
        Image(systemName: "checkmark")
          .foregroundColor(.blue)
          .font(.title2.weight(.bold))
      }
    }
  }
}

#Preview {
  NavigationStack {
    MapPreferencesView()
      .environmentObject(MapViewModel())
  }
}
