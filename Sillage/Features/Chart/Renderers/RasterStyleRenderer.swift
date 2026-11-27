//
//  RasterStyleRenderer.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import MapLibre
import OSLog

/// Manages raster base chart tiles (MBTiles, GeoGarage, OpenSeaMap) and the seamark overlay.
@MainActor
enum RasterStyleRenderer {

  /// Updates the base chart source and its raster layer, preserving Z-Index ordering.
  static func updateChartSource(_ source: ChartSource, in style: MLNStyle, isOverlayEnabled: Bool) {
    MapStyleStack.removeLayersAndSources(
      layers: [.baseRaster],
      sources: [.baseRaster],
      from: style
    )

    let sourceID = MapSourceIdentifier.baseRaster.rawValue
    guard let rasterSource = source.createTileSource(identifier: sourceID) else {
      Logger.mapStyle.error("Failed to create tile source for \(sourceID, privacy: .public)")
      return
    }

    style.addSource(rasterSource)
    Logger.mapStyle.debug("Added base raster source: \(sourceID, privacy: .public)")

    let rasterLayer = MLNRasterStyleLayer(
      identifier: MapLayerIdentifier.baseRaster.rawValue,
      source: rasterSource
    )
    MapStyleStack.insertLayer(rasterLayer, identifier: .baseRaster, into: style)

    updateOpenSeaMapOverlay(isEnabled: isOverlayEnabled, in: style)
  }

  /// Toggles the OpenSeaMap seamarks overlay layer.
  /// Dynamically removes the raster source when disabled so MapLibre never fetches remote tiles in the background.
  static func updateOpenSeaMapOverlay(isEnabled: Bool, in style: MLNStyle) {
    let layerID = MapLayerIdentifier.seamarkOverlay.rawValue
    let sourceID = MapSourceIdentifier.seamarkOverlay.rawValue

    if isEnabled {
      guard style.layer(withIdentifier: layerID) == nil else { return }

      let seamarkSource: MLNRasterTileSource
      if let existing = style.source(withIdentifier: sourceID) as? MLNRasterTileSource {
        seamarkSource = existing
      } else {
        seamarkSource = SeamarkSourceProvider.createTileSource(identifier: sourceID)
        style.addSource(seamarkSource)
        Logger.mapStyle.debug("Added seamark overlay source: \(sourceID, privacy: .public)")
      }

      let seamarkLayer = MLNRasterStyleLayer(identifier: layerID, source: seamarkSource)
      MapStyleStack.insertLayer(seamarkLayer, identifier: .seamarkOverlay, into: style)
      Logger.mapStyle.debug("Inserted seamark overlay layer at Z-Index: \(MapLayerIdentifier.seamarkOverlay.zIndex, privacy: .public)")
    } else {
      MapStyleStack.removeLayersAndSources(
        layers: [.seamarkOverlay],
        sources: [.seamarkOverlay],
        from: style
      )
    }
  }
}
