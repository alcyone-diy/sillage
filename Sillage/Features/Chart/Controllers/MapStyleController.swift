//
//  MapStyleController.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import MapLibre
import OSLog
import SwiftUI
import UIKit

/// Typed and ordered map layer identifiers with semantic Z-Index ordering.
enum MapLayerIdentifier: String, CaseIterable, Comparable {
  case baseRaster = "base-raster-layer"
  case seamarkOverlay = "seamark-overlay-layer"
  case gpsAccuracyFill = "gps-accuracy-layer"
  case gpsAccuracyStroke = "gps-accuracy-stroke-layer"
  case savedTrack = "saved-track-layer"
  case activeTrack = "active-track-layer"
  case bearingLine = "bearing-line-layer"
  case visibleWaypoints = "visible-waypoints-layer"
  case goToWaypoint = "goto-waypoint-layer"
  case anchorRadiusFill = "anchor-radius-layer"
  case anchorRadiusStroke = "anchor-radius-stroke-layer"
  case anchorPoint = "anchor-point-layer"
  case headingLine = "heading-vector-layer"
  case headingTick = "heading-vector-tick-layer"
  case vesselSymbol = "vessel-layer"

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
  case gpsAccuracy = "gps-accuracy-source"
  case savedTrack = "saved-track-source"
  case activeTrack = "active-track-source"
  case bearingLine = "bearing-line-source"
  case visibleWaypoints = "visible-waypoints-source"
  case goToWaypoint = "goto-waypoint-source"
  case heading = "heading-vector-source"
  case vessel = "vessel-source"
  case anchorRadius = "anchor-radius-source"
  case anchorPoint = "anchor-point-source"
}

/// Stateless MapLibre style worker.
/// All operations are isolated to the `@MainActor`.
@MainActor
struct MapStyleController {

  /// Inserts a layer into the MapLibre style at its correct Z-Index position.
  /// Searches for the first existing higher layer in the style and inserts below it.
  static func insertLayer(_ layer: MLNStyleLayer, identifier: MapLayerIdentifier, into style: MLNStyle) {
    assert(layer.identifier == identifier.rawValue, "FATAL: MLNStyleLayer identifier (\(layer.identifier)) does not match MapLayerIdentifier (\(identifier.rawValue)).")

    guard style.layer(withIdentifier: identifier.rawValue) == nil else {
      Logger.mapStyle.debug("Layer already present in style: \(identifier.rawValue, privacy: .public)")
      return
    }

    // Find higher Z-Index ordered layers
    let higherIdentifiers = MapLayerIdentifier.allCases.filter { $0 > identifier }

    for higherID in higherIdentifiers {
      if let higherLayer = style.layer(withIdentifier: higherID.rawValue) {
        style.insertLayer(layer, below: higherLayer)
        Logger.mapStyle.debug("Inserted layer '\(identifier.rawValue, privacy: .public)' below '\(higherID.rawValue, privacy: .public)'")
        return
      }
    }

    // If no higher layer exists in style yet, add to top
    style.addLayer(layer)
    Logger.mapStyle.debug("Added layer '\(identifier.rawValue, privacy: .public)' at top of style stack")
  }

  /// Updates the base chart source (local MBTiles, GeoGarage, OpenSeaMap) and its layer.
  static func updateChartSource(_ source: ChartSource, in style: MLNStyle, isOverlayEnabled: Bool) {
    let layerID = MapLayerIdentifier.baseRaster.rawValue
    let sourceID = MapSourceIdentifier.baseRaster.rawValue

    // 1. Remove existing layer
    if let existingLayer = style.layer(withIdentifier: layerID) {
      style.removeLayer(existingLayer)
      Logger.mapStyle.debug("Removed existing base raster layer: \(layerID, privacy: .public)")
    }

    // 2. Remove existing source
    if let existingSource = style.source(withIdentifier: sourceID) {
      style.removeSource(existingSource)
      Logger.mapStyle.debug("Removed existing base raster source: \(sourceID, privacy: .public)")
    }

    // 3. Create new tile source delegated to ChartSource model
    guard let rasterSource = source.createTileSource(identifier: sourceID) else {
      Logger.mapStyle.error("Failed to create tile source for \(sourceID, privacy: .public)")
      return
    }

    // 4. Defensively insert source and layer using Z-Index algorithm
    style.addSource(rasterSource)
    Logger.mapStyle.debug("Added base raster source: \(sourceID, privacy: .public)")

    let rasterLayer = MLNRasterStyleLayer(identifier: layerID, source: rasterSource)
    insertLayer(rasterLayer, identifier: .baseRaster, into: style)

    // 5. Re-apply OpenSeaMap overlay if enabled
    if isOverlayEnabled {
      updateOpenSeaMapOverlay(isEnabled: true, in: style)
    }
  }

  /// Toggles the OpenSeaMap seamarks overlay layer.
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
      insertLayer(seamarkLayer, identifier: .seamarkOverlay, into: style)
      Logger.mapStyle.debug("Inserted seamark overlay layer at Z-Index: \(MapLayerIdentifier.seamarkOverlay.zIndex)")
    } else {
      if let layer = style.layer(withIdentifier: layerID) {
        style.removeLayer(layer)
        Logger.mapStyle.debug("Removed seamark overlay layer: \(layerID, privacy: .public)")
      }
      if let source = style.source(withIdentifier: sourceID) {
        style.removeSource(source)
        Logger.mapStyle.debug("Removed seamark overlay source: \(sourceID, privacy: .public)")
      }
    }
  }

  // MARK: - Telemetry (Vessel, Heading, GPS Accuracy)

  /// Ensures telemetry sources and layers (GPS accuracy, heading vector, vessel cursor) exist.
  static func ensureTelemetryLayersExist(in style: MLNStyle, theme: MarineTheme) {
    if style.source(withIdentifier: MapSourceIdentifier.vessel.rawValue) == nil {
      // 1. GPS Accuracy Source & Layers
      let gpsSource = MLNShapeSource(identifier: MapSourceIdentifier.gpsAccuracy.rawValue, shape: nil, options: nil)
      style.addSource(gpsSource)

      let gpsFillLayer = MLNFillStyleLayer(identifier: MapLayerIdentifier.gpsAccuracyFill.rawValue, source: gpsSource)
      gpsFillLayer.fillColor = NSExpression(forConstantValue: UIColor(theme.colors.accent))
      gpsFillLayer.fillOpacity = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyFillOpacity)
      insertLayer(gpsFillLayer, identifier: .gpsAccuracyFill, into: style)

      let gpsStrokeLayer = MLNLineStyleLayer(identifier: MapLayerIdentifier.gpsAccuracyStroke.rawValue, source: gpsSource)
      gpsStrokeLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.accent))
      gpsStrokeLayer.lineOpacity = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyStrokeOpacity)
      gpsStrokeLayer.lineWidth = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyLineWidth)
      insertLayer(gpsStrokeLayer, identifier: .gpsAccuracyStroke, into: style)

      // 2. Heading / COG Vector Source & Layers
      let headingSource = MLNShapeSource(identifier: MapSourceIdentifier.heading.rawValue, shape: nil, options: nil)
      style.addSource(headingSource)

      let headingLineLayer = MLNLineStyleLayer(identifier: MapLayerIdentifier.headingLine.rawValue, source: headingSource)
      headingLineLayer.predicate = NSPredicate(format: "featureType == 'vectorLine'")
      headingLineLayer.lineWidth = NSExpression(forConstantValue: MarineTheme.ChartMetrics.headingLineWidth)
      headingLineLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.vectorCOG))
      insertLayer(headingLineLayer, identifier: .headingLine, into: style)

      let headingTickLayer = MLNCircleStyleLayer(identifier: MapLayerIdentifier.headingTick.rawValue, source: headingSource)
      headingTickLayer.predicate = NSPredicate(format: "featureType == 'vectorTick'")
      headingTickLayer.circleRadius = NSExpression(format: "TERNARY(isMajorTick == YES, 4.0, 2.0)")
      headingTickLayer.circleColor = NSExpression(forConstantValue: UIColor(theme.colors.vectorTick))
      headingTickLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.0)
      headingTickLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.systemBackground)
      insertLayer(headingTickLayer, identifier: .headingTick, into: style)

      // 3. Vessel Cursor Source & Layer
      let vesselSource = MLNShapeSource(identifier: MapSourceIdentifier.vessel.rawValue, shape: nil, options: nil)
      style.addSource(vesselSource)

      let vesselSymbolLayer = MLNSymbolStyleLayer(identifier: MapLayerIdentifier.vesselSymbol.rawValue, source: vesselSource)
      vesselSymbolLayer.iconImageName = NSExpression(forConstantValue: "vessel-cursor")
      vesselSymbolLayer.iconRotationAlignment = NSExpression(forConstantValue: "map")
      vesselSymbolLayer.iconRotation = NSExpression(forKeyPath: "course")
      vesselSymbolLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      vesselSymbolLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      vesselSymbolLayer.iconOpacity = NSExpression(forConstantValue: 1.0)
      insertLayer(vesselSymbolLayer, identifier: .vesselSymbol, into: style)
    }
  }

  /// Updates vessel position and orientation on the MapLibre style.
  static func updateVessel(state: VesselVisualState?, in style: MLNStyle, theme: MarineTheme) {
    ensureTelemetryLayersExist(in: style, theme: theme)
    if let source = style.source(withIdentifier: MapSourceIdentifier.vessel.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createVesselFeature(from: state)
    }
  }

  /// Updates heading / COG vector on the MapLibre style.
  static func updateHeadingVector(data: HeadingVectorData?, in style: MLNStyle, theme: MarineTheme) {
    ensureTelemetryLayersExist(in: style, theme: theme)
    if let source = style.source(withIdentifier: MapSourceIdentifier.heading.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createHeadingVectorFeature(from: data)
    }
  }

  /// Updates GPS accuracy polygon on the MapLibre style.
  static func updateGpsAccuracy(state: GpsAccuracyVisualState?, in style: MLNStyle, theme: MarineTheme) {
    ensureTelemetryLayersExist(in: style, theme: theme)
    if let source = style.source(withIdentifier: MapSourceIdentifier.gpsAccuracy.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createAccuracyFeature(from: state)
    }
  }

  /// Adjusts vessel cursor opacity based on data staleness.
  static func updateDataStaleState(isStale: Bool, in style: MLNStyle) {
    if let layer = style.layer(withIdentifier: MapLayerIdentifier.vesselSymbol.rawValue) as? MLNSymbolStyleLayer {
      layer.iconOpacity = NSExpression(forConstantValue: isStale ? 0.4 : 1.0)
    }
  }
}
