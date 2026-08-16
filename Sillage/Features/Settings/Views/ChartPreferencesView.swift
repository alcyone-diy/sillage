//
//  ChartPreferencesView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import UniformTypeIdentifiers

/// A view that allows the user to manage chart settings, including selecting
/// the active map source (local or remote) and importing new offline charts.
struct ChartPreferencesView: View {
  
  /// The central view model managing the map's state and data sources.
  @Environment(ChartViewModel.self) var chartViewModel
  /// Injects the global design system theme.
  @Environment(\.marineTheme) private var marineTheme
  
  @Environment(AppEnvironment.self) private var appEnvironment

  /// Controls the presentation of the system file picker for importing charts.
  @State private var showingFileImporter = false

  /// An internal helper enum to simplify determining which broad category of map source is currently active,
  /// facilitating UI updates (like showing checkmarks on the correct row).
  private enum ChartSourceSelection {
    case local
    case remote
    case openSeaMap
  }

  /// Computed property that maps the specific `currentChartSource` from the view model
  /// to a generic `ChartSourceSelection` category for UI rendering.
  private var currentSelection: ChartSourceSelection {
    switch chartViewModel.currentChartSource {
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
    @Bindable var chartViewModel = chartViewModel
    
    Form {
      // MARK: - Map Sources Section
      Section(header: Text("Map Sources").marineFont(.headline)) {

        // Free OpenSeaMap source (Default Fallback)
        Button(action: {
          chartViewModel.switchChartSource(to: .openSeaMap)
        }) {
          ChartSourceRowView(
            title: "OpenSeaMap (Free)",
            subtitle: "Global map",
            isSelected: currentSelection == .openSeaMap
          )
          .marineListCell()
        }
        .buttonStyle(.plain)

        // Dynamically list all imported local MBTiles files
        ForEach(chartViewModel.localOfflineCharts, id: \.filename) { mapFile in
          let url = mapFile.fileURL
          
          let isSelected = currentSelection == .local && {
            if case .localMBTiles(let currentURL) = chartViewModel.currentChartSource {
              return currentURL == url
            }
            return false
          }()

          let subtitle = mapFile.fileSize != nil
            ? "Imported map - \(byteFormatter.string(from: mapFile.fileSize!))"
            : "Imported map"

          Button(action: {
            chartViewModel.switchChartSource(to: .localMBTiles(url: url))
          }) {
            ChartSourceRowView(
              title: mapFile.filename,
              subtitle: subtitle,
              isSelected: isSelected
            )
            .marineListCell()
          }
          .buttonStyle(.plain)
        }
        
        // List all authorized GeoGarage layers fetched from the API
        if !chartViewModel.availableGeoGarageLayers.isEmpty {
          ForEach(chartViewModel.availableGeoGarageLayers) { layer in
            let isSelected = currentSelection == .remote && {
              if case .remoteGeoGarage(_, let currentLayerID) = chartViewModel.currentChartSource {
                return currentLayerID == layer.layer
              }
              return false
            }()

            Button(action: {
              chartViewModel.switchChartSource(to: .remoteGeoGarage(clientID: AppConfiguration.shared.geoGarageClientID, layerID: layer.layer))
            }) {
              ChartSourceRowView(
                title: layer.brandName,
                subtitle: "Valid until \(layer.validUntil)",
                isSelected: isSelected
              )
              .marineListCell()
            }
            .buttonStyle(.plain)
          }
        }
      }

      // MARK: - Accounts & Services
      Section(header: Text("Accounts & Services").marineFont(.headline)) {
        NavigationLink(destination: GeoGarageLoginView(offlineMapManager: appEnvironment.offlineMapManager)) {
          Text(chartViewModel.isGeoGarageAuthenticated ? "Manage GeoGarage Account" : "Login to GeoGarage")
            .marineFont(.body)
        }
        .marineListCell()

        // Button triggering the iOS native file picker
        Button("Import Offline Map (.mbtiles)…") {
          showingFileImporter = true
        }
        .marineFont(.body)
        .foregroundColor(.primary)
        .marineListCell()
      }
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .marineListBackground()
    .navigationTitle("Chart Preferences")
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
          chartViewModel.importOfflineChart(from: url)
        }
      case .failure(let error):
        chartViewModel.chartImportError = error.localizedDescription
        chartViewModel.showImportError = true
      }
    }
    
    // MARK: - Error Handling Alert
    .alert(isPresented: $chartViewModel.showImportError) {
      Alert(
        title: Text("Import Failed"),
        message: Text(chartViewModel.chartImportError ?? "Unknown error occurred."),
        dismissButton: .default(Text("OK"))
      )
    }
  }
}

/// A reusable UI component representing a single selectable row in the map sources list.
private struct ChartSourceRowView: View {
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
        Image(marineIcon: .save)
          .foregroundColor(.blue)
          .font(.title2.weight(.bold))
      }
    }
  }
}
