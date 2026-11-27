//
//  MapStyleStack.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import MapLibre
import OSLog

/// Typed and ordered map layer identifiers with semantic Z-Index ordering.
enum MapLayerIdentifier: String, CaseIterable, Comparable {
  case baseRaster = "base-raster-layer"
  case seamarkOverlay = "seamark-overlay-layer"
  case offlineMask = "offline-mask-layer"
  case offlineRegionsBorder = "offline-regions-border-layer"
  case offlineHighlightFill = "offline-highlight-fill-layer"
  case offlineHighlightBorder = "offline-highlight-border-layer"
  case offlineSelectionFill = "offline-selection-fill-layer"
  case offlineSelectionBorder = "offline-selection-border-layer"
  case offlineSelectionCorners = "offline-selection-corners-layer"
  case gpsAccuracyFill = "gps-accuracy-layer"
  case gpsAccuracyStroke = "gps-accuracy-stroke-layer"
  case savedTrack = "saved-track-layer"
  case activeTrack = "active-track-layer"
  case bearingLine = "bearing-line-layer"
  case measureLine = "measure-line-layer"
  case visibleWaypoints = "visible-waypoints-layer"
  case goToWaypoint = "goto-waypoint-layer"
  case anchorRadiusFill = "anchor-radius-layer"
  case anchorRadiusStrokeDashed = "anchor-radius-stroke-dashed-layer"
  case anchorRadiusStrokeSolid = "anchor-radius-stroke-solid-layer"
  case anchorSwingLine = "anchor-swing-layer"
  case anchorRodeLine = "anchor-rode-layer"
  case anchorPoint = "anchor-point-layer"
  case headingLine = "heading-vector-layer"
  case headingTick = "heading-vector-tick-layer"
  case vesselSymbol = "vessel-layer"
  case measurePins = "measure-pins-layer"
  case targetAimingCrosshair = "target-aiming-crosshair-layer"

  var zIndex: Int {
    Self.allCases.firstIndex(of: self) ?? 0
  }

  static func < (lhs: MapLayerIdentifier, rhs: MapLayerIdentifier) -> Bool {
    lhs.zIndex < rhs.zIndex
  }
}

/// Typed data source identifiers for the map.
enum MapSourceIdentifier: String, CaseIterable {
  case baseRaster = "base-raster-source"
  case seamarkOverlay = "openseamap_source"
  case offlineMask = "offline-mask-source"
  case offlineRegionsBorder = "offline-regions-border-source"
  case offlineHighlight = "offline-highlight-source"
  case offlineSelection = "offline-selection-source"
  case offlineSelectionCorners = "offline-selection-corners-source"
  case gpsAccuracy = "gps-accuracy-source"
  case savedTrack = "saved-track-source"
  case activeTrack = "active-track-source"
  case bearingLine = "bearing-line-source"
  case measureLine = "measure-line-source"
  case measurePins = "measure-pins-source"
  case visibleWaypoints = "visible-waypoints-source"
  case goToWaypoint = "goto-waypoint-source"
  case heading = "heading-vector-source"
  case vessel = "vessel-source"
  case anchorRadius = "anchor-radius-source"
  case anchorSwing = "anchor-swing-source"
  case anchorRode = "anchor-rode-source"
  case anchorPoint = "anchor-point-source"
  case targetAimingCrosshair = "target-aiming-crosshair-source"
}

/// Core Z-index ordered layer and source primitives for MapLibre styles.
@MainActor
enum MapStyleStack {

  /// Inserts a layer into the MapLibre style at its deterministic Z-Index position.
  /// Searches for the first existing higher layer in the style and inserts below it.
  static func insertLayer(_ layer: MLNStyleLayer, identifier: MapLayerIdentifier, into style: MLNStyle) {
    assert(
      layer.identifier == identifier.rawValue,
      "MLNStyleLayer identifier (\(layer.identifier)) does not match MapLayerIdentifier (\(identifier.rawValue))."
    )

    guard style.layer(withIdentifier: identifier.rawValue) == nil else {
      Logger.mapStyle.debug("Layer already present in style: \(identifier.rawValue, privacy: .public)")
      return
    }

    let higherIdentifiers = MapLayerIdentifier.allCases.filter { $0 > identifier }
    for higherID in higherIdentifiers {
      if let higherLayer = style.layer(withIdentifier: higherID.rawValue) {
        style.insertLayer(layer, below: higherLayer)
        Logger.mapStyle.debug("Inserted layer '\(identifier.rawValue, privacy: .public)' below '\(higherID.rawValue, privacy: .public)'")
        return
      }
    }

    style.addLayer(layer)
    Logger.mapStyle.debug("Added layer '\(identifier.rawValue, privacy: .public)' at top of style stack")
  }

  /// Idempotently retrieves or creates a GeoJSON shape source in the MapLibre style.
  @discardableResult
  static func ensureShapeSource(
    _ identifier: MapSourceIdentifier,
    options: [MLNShapeSourceOption: Any]? = nil,
    in style: MLNStyle
  ) -> MLNShapeSource {
    if let existing = style.source(withIdentifier: identifier.rawValue) as? MLNShapeSource {
      return existing
    }
    let source = MLNShapeSource(identifier: identifier.rawValue, shape: nil, options: options)
    style.addSource(source)
    return source
  }

  /// Completely removes specified layers and sources from the style stack.
  static func removeLayersAndSources(
    layers: [MapLayerIdentifier],
    sources: [MapSourceIdentifier],
    from style: MLNStyle
  ) {
    for layerID in layers {
      if let layer = style.layer(withIdentifier: layerID.rawValue) {
        style.removeLayer(layer)
        Logger.mapStyle.debug("Removed layer: \(layerID.rawValue, privacy: .public)")
      }
    }
    for sourceID in sources {
      if let source = style.source(withIdentifier: sourceID.rawValue) {
        style.removeSource(source)
        Logger.mapStyle.debug("Removed source: \(sourceID.rawValue, privacy: .public)")
      }
    }
  }
}
