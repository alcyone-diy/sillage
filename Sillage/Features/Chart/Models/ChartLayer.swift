//
//  ChartLayer.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import MapLibre

enum ChartSource: Equatable {
  case localMBTiles(url: URL)
  case localCaasChart(port: UInt16)
  case remoteGeoGarage(clientID: String, layerID: String)
  case openSeaMap

  /// Creates and configures the corresponding MLNRasterTileSource.
  @MainActor
  func createTileSource(identifier: String) -> MLNRasterTileSource? {

    switch self {
    case .localMBTiles(let activeMapPath):
      let mbtilesString = "mbtiles://" + activeMapPath.path
      let configURL: URL?
      if let encodedString = mbtilesString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
        configURL = URL(string: encodedString)
      } else {
        configURL = URL(string: mbtilesString)
      }
      guard let url = configURL else { return nil }
      return MLNRasterTileSource(identifier: identifier, configurationURL: url, tileSize: AppConstants.Cartography.Tile.rasterTileSize)

    case .localCaasChart(let port):
      let template = "http://127.0.0.1:\(port)/tiles/{z}/{x}/{y}.png"
      return MLNRasterTileSource(identifier: identifier, tileURLTemplates: [template], options: [
        .minimumZoomLevel: AppConstants.Cartography.Zoom.globalMinimum,
        .maximumZoomLevel: AppConstants.Cartography.Zoom.geoGarageMaximum,
        .tileSize: 256
      ])

    case .remoteGeoGarage(let clientID, let remoteLayerID):
      let template = "https://tiles.geogarage.com/\(clientID)/\(remoteLayerID)/{z}/{x}/{y}.png"
      return MLNRasterTileSource(identifier: identifier, tileURLTemplates: [template], options: [
        .minimumZoomLevel: AppConstants.Cartography.Zoom.globalMinimum,
        .maximumZoomLevel: AppConstants.Cartography.Zoom.geoGarageMaximum,
        .tileSize: 256
      ])

    case .openSeaMap:
      let template = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
      let attribution = MLNAttributionInfo(
        title: NSAttributedString(string: "© OpenStreetMap contributors"),
        url: URL(string: "https://www.openstreetmap.org/copyright")
      )
      return MLNRasterTileSource(identifier: identifier, tileURLTemplates: [template], options: [
        .minimumZoomLevel: AppConstants.Cartography.Zoom.globalMinimum,
        .maximumZoomLevel: AppConstants.Cartography.Zoom.openSeaMapMaximum,
        .attributionInfos: [attribution],
        .tileSize: AppConstants.Cartography.Tile.rasterTileSize
      ])
    }
  }
}

struct ChartLayer {
  /// The displayed name or identifier of the chart layer
  let name: LocalizedStringResource

  /// The chart source defining where the tiles come from
  let source: ChartSource
}

