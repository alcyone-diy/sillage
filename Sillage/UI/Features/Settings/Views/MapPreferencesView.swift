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
import UniformTypeIdentifiers

/// A view that allows the user to manage map settings, including selecting
/// the active map source (local or remote), importing new offline charts, and toggling overlays.
struct MapPreferencesView: View {
  
  /// The central view model managing the map's state and data sources.
  @Environment(MapViewModel.self) var mapViewModel
  
  /// Injects the global design system theme.
  @Environment(\.marineTheme) private var marineTheme
  
  /// Controls the presentation of the system file picker for importing charts.
  @State private var showingFileImporter = false

  /// An internal helper enum to simplify determining which broad category of map source is currently active,
  /// facilitating UI updates (like showing checkmarks on the correct row).
  private enum MapSourceSelection {
    case local
    case remote
    case openSeaMap
  }

  /// Computed property that maps the specific `currentMapSource` from the view model
  /// to a generic `MapSourceSelection` category for UI rendering.
  private var currentSelection: MapSourceSelection {
    switch mapViewModel.currentMapSource {
    case .localMBTiles:
      return .local
    case .remoteGeoGarage:
      return .remote
    case .openSeaMap:
      return .openSeaMap
    case .none:
      return .local // Default fallback
    }
  }

  /// A formatter used to display human-readable file sizes for local charts (e.g., "45.2 MB").
  private let byteFormatter: MeasurementFormatter = {
    let formatter = MeasurementFormatter()
    formatter.unitOptions = .naturalScale
    formatter.numberFormatter.maximumFractionDigits = 1
    return formatter
  }()

  var body: some View {
    // Allows creating bindings to the observable view model properties
    @Bindable var mapViewModel = mapViewModel
    
    Form {
      // MARK: - Local Offline Charts Section
      Section(header: Text("Local Offline Charts").marineFont(.headline)) {

        // Dynamically list all imported local MBTiles files
        ForEach(mapViewModel.localOfflineMaps, id: \.filename) { mapFile in
          let url = mapFile.fileURL
          
          // Check if this specific file is the one currently displayed on the map
          let isSelected = currentSelection == .local && {
            if case .localMBTiles(let currentURL) = mapViewModel.currentMapSource {
              return currentURL == url
            }
            return false
          }()

          // Prepare the subtitle, appending the file size if available from the metadata
          let subtitle = mapFile.fileSize != nil
            ? "Imported map - \(byteFormatter.string(from: mapFile.fileSize!))"
            : "Imported map"

          Button(action: {
            mapViewModel.switchMapSource(to: .localMBTiles(url: url))
          }) {
            MapSourceRowView(
              title: mapFile.filename,
              subtitle: subtitle,
              isSelected: isSelected
            )
            .marineListCell()
          }
          .buttonStyle(.plain)
        }
        
        // Button triggering the iOS native file picker
        Button("Import Offline Map (.mbtiles)…") {
          showingFileImporter = true
        }
        .marineFont(.body)
        .foregroundColor(.primary)
        .marineListCell()
      }

      // MARK: - Online Charts Section
      Section(header: Text("Online Charts (Internet Required)").marineFont(.headline)) {
        
        // Free OpenSeaMap source
        Button(action: {
          mapViewModel.switchMapSource(to: .openSeaMap)
        }) {
          MapSourceRowView(
            title: "OpenSeaMap (Free)",
            subtitle: "Global map",
            isSelected: currentSelection == .openSeaMap
          )
          .marineListCell()
        }
        .buttonStyle(.plain)

        // GeoGarage premium sources
        // If no layers are available, prompt the user to log in.
        if mapViewModel.availableGeoGarageLayers.isEmpty {
          NavigationLink(destination: GeoGarageLoginView()) {
            Text("Login to GeoGarage")
              .marineFont(.body)
          }
          .marineListCell()
        } else {
          // List all authorized GeoGarage layers fetched from the API
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

      // MARK: - Maritime Layers Section
      Section(header: Text("Maritime Layers").marineFont(.headline)) {
        Toggle(isOn: $mapViewModel.isOpenSeaMapOverlayEnabled) {
          VStack(alignment: .leading, spacing: 4) {
            Text("OpenSeaMap Seamarks")
              .marineFont(.body)
              .foregroundColor(.primary)
            Text("Navigational markers overlay. Zoom in (level 10+) on coasts to see marks.")
              .marineFont(.subheadline)
              .foregroundColor(.secondary)
          }
        }
        .tint(MarineTheme.Colors.primary)
        .marineListCell()
      }
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle("Map Preferences")
    .navigationBarTitleDisplayMode(.inline)
    
    // MARK: - File Importer Config
    .fileImporter(
      isPresented: $showingFileImporter,
      allowedContentTypes: [.mbtiles], // Restrict selection to .mbtiles only
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        if let url = urls.first {
          mapViewModel.importOfflineMap(from: url)
        }
      case .failure(let error):
        mapViewModel.mapImportError = error.localizedDescription
        mapViewModel.showImportError = true
      }
    }
    
    // MARK: - Error Handling Alert
    .alert(isPresented: $mapViewModel.showImportError) {
      Alert(
        title: Text("Import Failed"),
        message: Text(mapViewModel.mapImportError ?? "Unknown error occurred."),
        dismissButton: .default(Text("OK"))
      )
    }
  }
}

/// A reusable UI component representing a single selectable row in the map sources list.
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
      // Display a checkmark if this source is currently active
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
      .environment(MapViewModel())
      .environment(\.marineTheme, .standard)
  }
}
