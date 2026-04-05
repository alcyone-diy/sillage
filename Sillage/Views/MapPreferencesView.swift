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

        // Remote GeoGarage Button
        Button(action: {
          mapViewModel.switchMapSource(to: .remoteGeoGarage(clientID: AppConfiguration.shared.geoGarageClientID, layerID: AppConfiguration.shared.geoGarageLayerID))
        }) {
          MapSourceRowView(
            title: "Remote GeoGarage",
            subtitle: "Online marine charts",
            isSelected: currentSelection == .remote
          )
          .marineListCell()
        }
        .buttonStyle(.plain)

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
          .font(.body)
          .foregroundColor(.primary)
        Text(subtitle)
          .font(.subheadline)
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
