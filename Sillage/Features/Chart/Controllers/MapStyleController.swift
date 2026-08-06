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

  // MARK: - Navigation Layers (Tracks, Waypoints, Bearing Line, Anchor)

  /// Ensures navigation sources and layers (active track, saved track, waypoints, bearing line, anchor) exist.
  static func ensureNavigationLayersExist(in style: MLNStyle, theme: MarineTheme) {
    if style.source(withIdentifier: MapSourceIdentifier.activeTrack.rawValue) == nil {
      // 1. Active Track
      let activeTrackSource = MLNShapeSource(identifier: MapSourceIdentifier.activeTrack.rawValue, shape: nil, options: nil)
      style.addSource(activeTrackSource)

      let activeTrackLayer = MLNLineStyleLayer(identifier: MapLayerIdentifier.activeTrack.rawValue, source: activeTrackSource)
      activeTrackLayer.lineWidth = NSExpression(forConstantValue: 4.0)
      activeTrackLayer.lineColor = NSExpression(forConstantValue: UIColor.systemRed)
      insertLayer(activeTrackLayer, identifier: .activeTrack, into: style)

      // 2. Saved Track
      let savedTrackSource = MLNShapeSource(identifier: MapSourceIdentifier.savedTrack.rawValue, shape: nil, options: nil)
      style.addSource(savedTrackSource)

      let savedTrackLayer = MLNLineStyleLayer(identifier: MapLayerIdentifier.savedTrack.rawValue, source: savedTrackSource)
      savedTrackLayer.lineWidth = NSExpression(forConstantValue: 4.0)
      savedTrackLayer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
      insertLayer(savedTrackLayer, identifier: .savedTrack, into: style)

      // 3. Bearing Line
      let bearingLineSource = MLNShapeSource(identifier: MapSourceIdentifier.bearingLine.rawValue, shape: nil, options: nil)
      style.addSource(bearingLineSource)

      let bearingLineLayer = MLNLineStyleLayer(identifier: MapLayerIdentifier.bearingLine.rawValue, source: bearingLineSource)
      bearingLineLayer.lineWidth = NSExpression(forConstantValue: 1.5)
      bearingLineLayer.lineColor = NSExpression(forKeyPath: "color")
      bearingLineLayer.lineDashPattern = NSExpression(forConstantValue: [4.0, 4.0])
      insertLayer(bearingLineLayer, identifier: .bearingLine, into: style)

      // 4. Visible Waypoints
      let visibleWaypointsSource = MLNShapeSource(identifier: MapSourceIdentifier.visibleWaypoints.rawValue, shape: nil, options: nil)
      style.addSource(visibleWaypointsSource)

      let visibleWaypointsLayer = MLNCircleStyleLayer(identifier: MapLayerIdentifier.visibleWaypoints.rawValue, source: visibleWaypointsSource)
      visibleWaypointsLayer.circleRadius = NSExpression(forConstantValue: 6.0)
      visibleWaypointsLayer.circleColor = NSExpression(forKeyPath: "color")
      visibleWaypointsLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
      visibleWaypointsLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
      insertLayer(visibleWaypointsLayer, identifier: .visibleWaypoints, into: style)

      // 5. Target GoTo Waypoint
      let goToWaypointSource = MLNShapeSource(identifier: MapSourceIdentifier.goToWaypoint.rawValue, shape: nil, options: nil)
      style.addSource(goToWaypointSource)

      let goToWaypointLayer = MLNCircleStyleLayer(identifier: MapLayerIdentifier.goToWaypoint.rawValue, source: goToWaypointSource)
      goToWaypointLayer.circleRadius = NSExpression(forConstantValue: 8.0)
      goToWaypointLayer.circleColor = NSExpression(forKeyPath: "color")
      goToWaypointLayer.circleStrokeWidth = NSExpression(forConstantValue: 2.0)
      goToWaypointLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
      insertLayer(goToWaypointLayer, identifier: .goToWaypoint, into: style)

      // 6. Anchor Radius Fill, Stroke & Symbol Point
      let anchorRadiusSource = MLNShapeSource(identifier: MapSourceIdentifier.anchorRadius.rawValue, shape: nil, options: nil)
      style.addSource(anchorRadiusSource)

      let anchorRadiusLayer = MLNFillStyleLayer(identifier: MapLayerIdentifier.anchorRadiusFill.rawValue, source: anchorRadiusSource)
      anchorRadiusLayer.fillColor = NSExpression(forConstantValue: UIColor(theme.colors.anchorDropped))
      anchorRadiusLayer.fillOpacity = NSExpression(forConstantValue: 0.15)
      insertLayer(anchorRadiusLayer, identifier: .anchorRadiusFill, into: style)

      let anchorRadiusStrokeLayer = MLNLineStyleLayer(identifier: MapLayerIdentifier.anchorRadiusStroke.rawValue, source: anchorRadiusSource)
      anchorRadiusStrokeLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.anchorDropped))
      anchorRadiusStrokeLayer.lineWidth = NSExpression(forConstantValue: 1.5)
      anchorRadiusStrokeLayer.lineOpacity = NSExpression(forConstantValue: 0.8)
      insertLayer(anchorRadiusStrokeLayer, identifier: .anchorRadiusStroke, into: style)

      let anchorPointSource = MLNShapeSource(identifier: MapSourceIdentifier.anchorPoint.rawValue, shape: nil, options: nil)
      style.addSource(anchorPointSource)

      let anchorPointLayer = MLNSymbolStyleLayer(identifier: MapLayerIdentifier.anchorPoint.rawValue, source: anchorPointSource)
      anchorPointLayer.iconImageName = NSExpression(forConstantValue: "anchor-icon")
      anchorPointLayer.iconColor = NSExpression(forConstantValue: UIColor(theme.colors.anchorDropped))
      anchorPointLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      anchorPointLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      anchorPointLayer.iconScale = NSExpression(forConstantValue: 1.0)
      insertLayer(anchorPointLayer, identifier: .anchorPoint, into: style)
    }
  }

  /// Updates active track points feature on the MapLibre style.
  static func updateActiveTrack(points: ArraySlice<TrackPoint>, in style: MLNStyle, theme: MarineTheme) {
    ensureNavigationLayersExist(in: style, theme: theme)
    if let source = style.source(withIdentifier: MapSourceIdentifier.activeTrack.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createActiveTrackFeature(from: points)
    }
  }

  /// Updates saved track feature on the MapLibre style.
  static func updateSavedTrack(state: SavedTrackVisualState?, in style: MLNStyle, theme: MarineTheme) {
    ensureNavigationLayersExist(in: style, theme: theme)
    if let source = style.source(withIdentifier: MapSourceIdentifier.savedTrack.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createSavedTrackFeature(from: state)
    }
  }

  /// Updates visible waypoints on the MapLibre style.
  static func updateVisibleWaypoints(states: [WaypointVisualState], in style: MLNStyle, theme: MarineTheme) {
    ensureNavigationLayersExist(in: style, theme: theme)
    if let source = style.source(withIdentifier: MapSourceIdentifier.visibleWaypoints.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createVisibleWaypointsFeature(from: states)
    }
  }

  /// Updates target GoTo waypoint on the MapLibre style.
  static func updateGoToWaypoint(state: WaypointVisualState?, in style: MLNStyle, theme: MarineTheme) {
    ensureNavigationLayersExist(in: style, theme: theme)
    if let source = style.source(withIdentifier: MapSourceIdentifier.goToWaypoint.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createGoToWaypointFeature(from: state)
    }
  }

  /// Updates bearing line feature on the MapLibre style.
  static func updateBearingLine(state: BearingLineVisualState?, in style: MLNStyle, theme: MarineTheme) {
    ensureNavigationLayersExist(in: style, theme: theme)
    if let source = style.source(withIdentifier: MapSourceIdentifier.bearingLine.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createBearingLineFeature(from: state)
    }
  }

  /// Updates anchor features and layer styling on the MapLibre style.
  static func updateAnchor(state: AnchorVisualState?, in style: MLNStyle, theme: MarineTheme) {
    ensureNavigationLayersExist(in: style, theme: theme)
    let anchorFeatures = MapLibreFeatureFactory.createAnchorFeatures(from: state)
    if let source = style.source(withIdentifier: MapSourceIdentifier.anchorRadius.rawValue) as? MLNShapeSource {
      source.shape = anchorFeatures.radiusFeature
    }
    if let source = style.source(withIdentifier: MapSourceIdentifier.anchorPoint.rawValue) as? MLNShapeSource {
      source.shape = anchorFeatures.pointFeature
    }
    if let status = state?.status {
      updateAnchorLayerStyles(in: style, for: status, with: theme)
    }
  }

  /// Updates fill and stroke styles for the anchor radius and point layers based on status.
  private static func updateAnchorLayerStyles(in style: MLNStyle, for status: AnchorVisualStatus, with theme: MarineTheme) {
    if let pointLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorPoint.rawValue) as? MLNSymbolStyleLayer {
      let pointColor: UIColor = (status == .setup)
        ? UIColor(theme.colors.anchorDropped).withAlphaComponent(0.5)
        : UIColor(theme.colors.anchorDropped)
      pointLayer.iconColor = NSExpression(forConstantValue: pointColor)
    }

    guard let fillLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorRadiusFill.rawValue) as? MLNFillStyleLayer,
          let strokeLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorRadiusStroke.rawValue) as? MLNLineStyleLayer else {
      return
    }

    switch status {
    case .setup:
      fillLayer.fillOpacity = NSExpression(forConstantValue: 0.0)
      strokeLayer.lineOpacity = NSExpression(forConstantValue: 0.0)

    case .dropped:
      let color = UIColor(theme.colors.anchorDropped)
      fillLayer.fillColor = NSExpression(forConstantValue: color)
      fillLayer.fillOpacity = NSExpression(forConstantValue: 0.0)

      strokeLayer.lineColor = NSExpression(forConstantValue: color)
      strokeLayer.lineDashPattern = NSExpression(forConstantValue: [4.0, 4.0])
      strokeLayer.lineWidth = NSExpression(forConstantValue: 3.0)
      strokeLayer.lineOpacity = NSExpression(forConstantValue: 1.0)

    case .armed:
      let color = UIColor(theme.colors.anchorArmed)
      fillLayer.fillColor = NSExpression(forConstantValue: color)
      fillLayer.fillOpacity = NSExpression(forConstantValue: 0.10)

      strokeLayer.lineColor = NSExpression(forConstantValue: color)
      strokeLayer.lineDashPattern = nil
      strokeLayer.lineWidth = NSExpression(forConstantValue: 1.5)
      strokeLayer.lineOpacity = NSExpression(forConstantValue: 0.8)

    case .dragging:
      let color = UIColor(theme.colors.anchorDragging)
      fillLayer.fillColor = NSExpression(forConstantValue: color)
      fillLayer.fillOpacity = NSExpression(forConstantValue: 0.25)

      strokeLayer.lineColor = NSExpression(forConstantValue: color)
      strokeLayer.lineDashPattern = nil
      strokeLayer.lineWidth = NSExpression(forConstantValue: 1.5)
      strokeLayer.lineOpacity = NSExpression(forConstantValue: 1.0)
    }
  }
}

