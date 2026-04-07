//
//  OpenSeaMapLayerService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import MapLibre

class OpenSeaMapLayerService {

  static let shared = OpenSeaMapLayerService()

  private let sourceID = "openseamap_source"
  private let layerID = "openseamap_layer"
  private let templateURL = "https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png"

  private init() {}

  func addSeamarkLayer(to style: MLNStyle, above baseLayerID: String?) {
    // Prevent adding the source/layer multiple times
    if style.source(withIdentifier: sourceID) == nil {
      let source = MLNRasterTileSource(
        identifier: sourceID,
        tileURLTemplates: [templateURL],
        options: [
          .minimumZoomLevel: 0,
          .maximumZoomLevel: 18,
          .tileSize: 256,
          .attributionInfos: [
            MLNAttributionInfo(title: NSAttributedString(string: "Map data © OpenSeaMap contributors"), url: URL(string: "https://openseamap.org"))
          ]
        ]
      )
      style.addSource(source)
    }

    if style.layer(withIdentifier: layerID) == nil {
      guard let source = style.source(withIdentifier: sourceID) else { return }

      let layer = MLNRasterStyleLayer(identifier: layerID, source: source)

      // Set reasonable download priority to prevent UI hanging on weak network
      // (Note: MLNRasterStyleLayer does not expose tileMinimumDownloadPriority,
      // but we configure the source options to handle tile sizes optimally.
      // MLNStyle options and properties are set as appropriate).

      // Insert above the base map if specified and if the base layer exists
      if let baseID = baseLayerID, let baseLayer = style.layer(withIdentifier: baseID) {
        style.insertLayer(layer, above: baseLayer)
      } else {
        // Fallback: insert the layer at the very bottom (index 0) or right above the background layer
        // rather than blindly calling addLayer, which puts it at the absolute top (obscuring GPS pucks).
        if let firstLayer = style.layers.first {
          style.insertLayer(layer, above: firstLayer)
        } else {
          style.addLayer(layer)
        }
      }
    }
  }

  func removeSeamarkLayer(from style: MLNStyle) {
    if let layer = style.layer(withIdentifier: layerID) {
      style.removeLayer(layer)
    }

    // Also remove the source when the layer is removed to clean up
    if let source = style.source(withIdentifier: sourceID) {
      style.removeSource(source)
    }
  }
}
