//
//  SeamarkSourceProvider.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import MapLibre
import UIKit

/// Tile source provider for the OpenSeaMap seamark overlay.
@MainActor
enum SeamarkSourceProvider {
  /// Creates and configures the MLNRasterTileSource for seamarks.
  static func createTileSource(identifier: String) -> MLNRasterTileSource {
    let template = "https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png"
    let attribution = MLNAttributionInfo(
      title: NSAttributedString(string: "Map data © OpenSeaMap contributors"),
      url: URL(string: "https://openseamap.org")
    )
    return MLNRasterTileSource(
      identifier: identifier,
      tileURLTemplates: [template],
      options: [
        .minimumZoomLevel: AppConstants.Cartography.Zoom.globalMinimum,
        .maximumZoomLevel: AppConstants.Cartography.Zoom.openSeaMapMaximum,
        .tileSize: AppConstants.Cartography.Tile.rasterTileSize,
        .attributionInfos: [attribution]
      ]
    )
  }
}
