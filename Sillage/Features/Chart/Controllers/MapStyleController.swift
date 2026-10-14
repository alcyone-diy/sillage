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
  case offlineMask = "offline-mask-layer"
  case offlineRegionsBorder = "offline-regions-border-layer"
  case offlineHighlightFill = "offline-highlight-fill-layer"
  case offlineHighlightBorder = "offline-highlight-border-layer"
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
  case anchorEvitementLine = "anchor-evitement-layer"
  case anchorRodeLine = "anchor-rode-layer"
  case anchorPoint = "anchor-point-layer"
  case headingLine = "heading-vector-layer"
  case headingTick = "heading-vector-tick-layer"
  case vesselSymbol = "vessel-layer"
  case measurePins = "measure-pins-layer"
  case targetPin = "target-pin-layer"

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
  case gpsAccuracy = "gps-accuracy-source"
  case savedTrack = "saved-track-source"
  case activeTrack = "active-track-source"
  case bearingLine = "bearing-line-source"
  case measureLine = "measure-line-source"
  case measurePins = "measure-pins-source"
  case targetPin = "target-pin-source"
  case visibleWaypoints = "visible-waypoints-source"
  case goToWaypoint = "goto-waypoint-source"
  case heading = "heading-vector-source"
  case vessel = "vessel-source"
  case anchorRadius = "anchor-radius-source"
  case anchorEvitement = "anchor-evitement-source"
  case anchorRode = "anchor-rode-source"
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

    // 5. Update OpenSeaMap overlay according to isOverlayEnabled state
    updateOpenSeaMapOverlay(isEnabled: isOverlayEnabled, in: style)
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

  // MARK: - Generic Region Layers Helpers

  /// Ensures that fill and dashed outline border sources and layers exist for displaying geographic regions.
  private static func ensureRegionLayersExist(
    sourceID: MapSourceIdentifier,
    fillLayerID: MapLayerIdentifier,
    fillColor: UIColor,
    fillOpacity: Double,
    borderSourceID: MapSourceIdentifier? = nil,
    borderLayerID: MapLayerIdentifier,
    borderColor: UIColor,
    borderWidth: Double,
    borderOpacity: Double,
    dashPattern: [Double],
    in style: MLNStyle
  ) {
    let fillSource: MLNShapeSource
    if let existing = style.source(withIdentifier: sourceID.rawValue) as? MLNShapeSource {
      fillSource = existing
    } else {
      let newSource = MLNShapeSource(identifier: sourceID.rawValue, shape: nil, options: nil)
      style.addSource(newSource)
      fillSource = newSource
    }

    if style.layer(withIdentifier: fillLayerID.rawValue) == nil {
      let fillLayer = MLNFillStyleLayer(identifier: fillLayerID.rawValue, source: fillSource)
      fillLayer.fillColor = NSExpression(forConstantValue: fillColor)
      fillLayer.fillOpacity = NSExpression(forConstantValue: fillOpacity)
      insertLayer(fillLayer, identifier: fillLayerID, into: style)
    }

    let borderSource: MLNShapeSource
    if let borderSourceID {
      if let existing = style.source(withIdentifier: borderSourceID.rawValue) as? MLNShapeSource {
        borderSource = existing
      } else {
        let newSource = MLNShapeSource(identifier: borderSourceID.rawValue, shape: nil, options: nil)
        style.addSource(newSource)
        borderSource = newSource
      }
    } else {
      borderSource = fillSource
    }

    if style.layer(withIdentifier: borderLayerID.rawValue) == nil {
      let borderLayer = MLNLineStyleLayer(identifier: borderLayerID.rawValue, source: borderSource)
      borderLayer.lineColor = NSExpression(forConstantValue: borderColor)
      borderLayer.lineWidth = NSExpression(forConstantValue: borderWidth)
      borderLayer.lineOpacity = NSExpression(forConstantValue: borderOpacity)
      borderLayer.lineDashPattern = NSExpression(forConstantValue: dashPattern)
      insertLayer(borderLayer, identifier: borderLayerID, into: style)
    }
  }

  /// Completely removes specified layers and sources cleanly from the style stack.
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

  // MARK: - Offline Mask (Unsaved Map Dimming)

  /// Ensures offline mask fill and border sources/layers exist in the MapLibre style.
  static func ensureOfflineMaskLayersExist(in style: MLNStyle, theme: MarineTheme) {
    ensureRegionLayersExist(
      sourceID: .offlineMask,
      fillLayerID: .offlineMask,
      fillColor: UIColor(theme.colors.overlay),
      fillOpacity: MarineTheme.ChartMetrics.offlineMaskFillOpacity,
      borderSourceID: .offlineRegionsBorder,
      borderLayerID: .offlineRegionsBorder,
      borderColor: UIColor(theme.colors.accent),
      borderWidth: MarineTheme.ChartMetrics.offlineRegionsBorderLineWidth,
      borderOpacity: MarineTheme.ChartMetrics.offlineRegionsBorderOpacity,
      dashPattern: [4.0, 3.0],
      in: style
    )
  }

  /// Completely removes all offline mask and border layers and sources from the style stack.
  /// Guarantees no ghost layers or unused shape sources remain when selection mode is deactivated.
  static func removeOfflineMaskLayers(from style: MLNStyle) {
    removeLayersAndSources(
      layers: [.offlineRegionsBorder, .offlineMask],
      sources: [.offlineRegionsBorder, .offlineMask],
      from: style
    )
  }

  /// Updates the offline mask and region borders on the MapLibre style.
  /// If state is nil or inactive, completely cleans up and removes all offline mask layers and sources.
  static func updateOfflineMask(state: OfflineMaskVisualState?, in style: MLNStyle, theme: MarineTheme) {
    guard let state, state.isActive else {
      removeOfflineMaskLayers(from: style)
      return
    }

    ensureOfflineMaskLayersExist(in: style, theme: theme)

    if let maskSource = style.source(withIdentifier: MapSourceIdentifier.offlineMask.rawValue) as? MLNShapeSource {
      maskSource.shape = MapLibreFeatureFactory.createOfflineMaskFeature(from: state)
    }

    if let borderSource = style.source(withIdentifier: MapSourceIdentifier.offlineRegionsBorder.rawValue) as? MLNShapeSource {
      borderSource.shape = MapLibreFeatureFactory.createOfflineRegionsBorderFeature(from: state)
    }
  }

  // MARK: - Highlighted Offline Region Preview

  /// Ensures highlighted offline region fill and border sources/layers exist in the MapLibre style.
  static func ensureOfflineHighlightLayersExist(in style: MLNStyle, theme: MarineTheme) {
    ensureRegionLayersExist(
      sourceID: .offlineHighlight,
      fillLayerID: .offlineHighlightFill,
      fillColor: UIColor(theme.colors.accent),
      fillOpacity: 0.12,
      borderLayerID: .offlineHighlightBorder,
      borderColor: UIColor(theme.colors.accent),
      borderWidth: 2.5,
      borderOpacity: 0.9,
      dashPattern: [6.0, 3.0],
      in: style
    )
  }

  /// Completely removes all highlighted offline region layers and source from the style stack.
  static func removeOfflineHighlightLayers(from style: MLNStyle) {
    removeLayersAndSources(
      layers: [.offlineHighlightBorder, .offlineHighlightFill],
      sources: [.offlineHighlight],
      from: style
    )
  }

  /// Updates the highlighted offline region on the MapLibre style.
  /// If region is nil, cleanly removes all highlight layers and sources.
  static func updateOfflineHighlight(region: HighlightedOfflineRegion?, in style: MLNStyle, theme: MarineTheme) {
    guard let region else {
      removeOfflineHighlightLayers(from: style)
      return
    }

    ensureOfflineHighlightLayersExist(in: style, theme: theme)

    if let source = style.source(withIdentifier: MapSourceIdentifier.offlineHighlight.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createOfflineHighlightFeature(from: region.bounds)
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
      vesselSymbolLayer.iconAnchor = NSExpression(forConstantValue: "center")
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

  /// Ensures all 4 anchor status icons are registered in the MapLibre style stack.
  static func ensureAnchorImagesExist(in style: MLNStyle, theme: MarineTheme) {
    let anchorStatuses: [AnchorVisualStatus] = [.setup, .dropped, .armed, .dragging]
    for status in anchorStatuses {
      let imageName = "anchor-icon-\(status.rawValue)"
      if let image = AnchorGraphicsFactory.createAnchorImage(for: status, theme: theme) {
        if style.image(forName: imageName) !== image {
          style.setImage(image, forName: imageName)
          Logger.mapStyle.debug("Registered anchor icon image for status \(status.rawValue, privacy: .public)")
        }
      }
    }
  }

  /// Ensures all 4 measure pin icon images (A/B, selected/idle) are registered in the MapLibre style stack.
  static func ensureMeasurePinImagesExist(in style: MLNStyle, theme: MarineTheme) {
    let pins: [ActiveMeasurePin] = [.start, .end]
    let states: [Bool] = [true, false]
    for pin in pins {
      let pinLetter = pin == .start ? "a" : "b"
      for isSelected in states {
        let stateKey = isSelected ? "selected" : "idle"
        let imageName = "measure-pin-\(pinLetter)-\(stateKey)"
        if let image = MarinePinGraphicsFactory.createMeasurePinImage(for: pin, isSelected: isSelected, theme: theme) {
          if style.image(forName: imageName) !== image {
            style.setImage(image, forName: imageName)
            Logger.mapStyle.debug("Updated measure pin icon image \(imageName, privacy: .public)")
          }
        }
      }
    }
  }

  /// Ensures both target pin icon images (idle and dragging) are registered in the MapLibre style stack.
  static func ensureTargetPinImagesExist(in style: MLNStyle, theme: MarineTheme) {
    let states: [(Bool, String)] = [(false, "target-pin-idle"), (true, "target-pin-dragging")]
    for (isDragging, imageName) in states {
      if let image = MarinePinGraphicsFactory.createTargetPinImage(isDragging: isDragging, theme: theme) {
        if style.image(forName: imageName) !== image {
          style.setImage(image, forName: imageName)
          Logger.mapStyle.debug("Updated target pin icon image \(imageName, privacy: .public)")
        }
      }
    }
  }

  // MARK: - Navigation Layers (Tracks, Waypoints, Bearing Line, Anchor)

  /// Ensures navigation sources and layers (active track, saved track, waypoints, bearing line, anchor) exist.
  static func ensureNavigationLayersExist(in style: MLNStyle, theme: MarineTheme) {
    style.performsPlacementTransitions = false
    if style.source(withIdentifier: MapSourceIdentifier.activeTrack.rawValue) == nil {
      ensureAnchorImagesExist(in: style, theme: theme)
      ensureMeasurePinImagesExist(in: style, theme: theme)
      ensureTargetPinImagesExist(in: style, theme: theme)

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

      // 3b. Measure Line
      let measureLineSource = MLNShapeSource(identifier: MapSourceIdentifier.measureLine.rawValue, shape: nil, options: nil)
      style.addSource(measureLineSource)

      let measureLineLayer = MLNLineStyleLayer(identifier: MapLayerIdentifier.measureLine.rawValue, source: measureLineSource)
      measureLineLayer.lineWidth = NSExpression(forConstantValue: 2.5)
      measureLineLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.accent))
      measureLineLayer.lineDashPattern = NSExpression(forConstantValue: [4.0, 4.0])
      insertLayer(measureLineLayer, identifier: .measureLine, into: style)

      // 4. Visible Waypoints
      let visibleWaypointsSource = MLNShapeSource(identifier: MapSourceIdentifier.visibleWaypoints.rawValue, shape: nil, options: nil)
      style.addSource(visibleWaypointsSource)

      let visibleWaypointsLayer = MLNCircleStyleLayer(identifier: MapLayerIdentifier.visibleWaypoints.rawValue, source: visibleWaypointsSource)
      visibleWaypointsLayer.circleRadius = NSExpression(
        forConditional: NSPredicate(format: "isCalloutTarget == true"),
        trueExpression: NSExpression(forConstantValue: 12.0),
        falseExpression: NSExpression(forConstantValue: 6.0)
      )
      visibleWaypointsLayer.circleColor = NSExpression(forKeyPath: "color")
      visibleWaypointsLayer.circleStrokeWidth = NSExpression(
        forConditional: NSPredicate(format: "isCalloutTarget == true"),
        trueExpression: NSExpression(forConstantValue: 3.0),
        falseExpression: NSExpression(forConstantValue: 1.5)
      )
      visibleWaypointsLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
      insertLayer(visibleWaypointsLayer, identifier: .visibleWaypoints, into: style)

      // 5. Target GoTo Waypoint
      let goToWaypointSource = MLNShapeSource(identifier: MapSourceIdentifier.goToWaypoint.rawValue, shape: nil, options: nil)
      style.addSource(goToWaypointSource)

      let goToWaypointLayer = MLNCircleStyleLayer(identifier: MapLayerIdentifier.goToWaypoint.rawValue, source: goToWaypointSource)
      goToWaypointLayer.circleRadius = NSExpression(
        forConditional: NSPredicate(format: "isCalloutTarget == true"),
        trueExpression: NSExpression(forConstantValue: 14.0),
        falseExpression: NSExpression(forConstantValue: 8.0)
      )
      goToWaypointLayer.circleColor = NSExpression(forKeyPath: "color")
      goToWaypointLayer.circleStrokeWidth = NSExpression(
        forConditional: NSPredicate(format: "isCalloutTarget == true"),
        trueExpression: NSExpression(forConstantValue: 3.5),
        falseExpression: NSExpression(forConstantValue: 2.0)
      )
      goToWaypointLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
      insertLayer(goToWaypointLayer, identifier: .goToWaypoint, into: style)

      // 5b. Measure Pins (positioned above all waypoints)
      let measurePinsSource = MLNShapeSource(identifier: MapSourceIdentifier.measurePins.rawValue, shape: nil, options: nil)
      style.addSource(measurePinsSource)

      let measurePinsLayer = MLNSymbolStyleLayer(identifier: MapLayerIdentifier.measurePins.rawValue, source: measurePinsSource)
      measurePinsLayer.iconImageName = NSExpression(forKeyPath: "icon")
      measurePinsLayer.iconAnchor = NSExpression(forConstantValue: "top")
      measurePinsLayer.iconOffset = NSExpression(forConstantValue: [0.0, -MarinePinGraphicsFactory.focalPointY])
      measurePinsLayer.iconRotationAlignment = NSExpression(forConstantValue: "viewport")
      measurePinsLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      measurePinsLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      measurePinsLayer.symbolSortKey = NSExpression(forKeyPath: "sortKey")
      measurePinsLayer.iconOpacity = NSExpression(forConstantValue: 1.0)
      measurePinsLayer.iconOpacityTransition = MLNTransition(duration: 0, delay: 0)
      insertLayer(measurePinsLayer, identifier: .measurePins, into: style)

      // 5c. Contextual Target Pin (for callout target selection)
      let targetPinSource = MLNShapeSource(identifier: MapSourceIdentifier.targetPin.rawValue, shape: nil, options: nil)
      style.addSource(targetPinSource)

      let targetPinLayer = MLNSymbolStyleLayer(identifier: MapLayerIdentifier.targetPin.rawValue, source: targetPinSource)
      targetPinLayer.iconImageName = NSExpression(forKeyPath: "icon")
      targetPinLayer.iconAnchor = NSExpression(forConstantValue: "top")
      targetPinLayer.iconOffset = NSExpression(forConstantValue: [0.0, -MarinePinGraphicsFactory.focalPointY])
      targetPinLayer.iconRotationAlignment = NSExpression(forConstantValue: "viewport")
      targetPinLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      targetPinLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      targetPinLayer.iconOpacity = NSExpression(forConstantValue: 1.0)
      targetPinLayer.iconOpacityTransition = MLNTransition(duration: 0, delay: 0)
      insertLayer(targetPinLayer, identifier: .targetPin, into: style)

      // 6. Anchor Radius Fill, Stroke, Rode Line & Symbol Point
      let anchorRadiusSource = MLNShapeSource(identifier: MapSourceIdentifier.anchorRadius.rawValue, shape: nil, options: nil)
      style.addSource(anchorRadiusSource)

      let anchorRadiusLayer = MLNFillStyleLayer(identifier: MapLayerIdentifier.anchorRadiusFill.rawValue, source: anchorRadiusSource)
      anchorRadiusLayer.fillColor = NSExpression(forConstantValue: UIColor(theme.colors.anchorDropped))
      anchorRadiusLayer.fillOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.armedFillOpacity)
      insertLayer(anchorRadiusLayer, identifier: .anchorRadiusFill, into: style)

      let anchorRadiusStrokeDashedLayer = MLNLineStyleLayer(identifier: MapLayerIdentifier.anchorRadiusStrokeDashed.rawValue, source: anchorRadiusSource)
      anchorRadiusStrokeDashedLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.anchorDropped))
      anchorRadiusStrokeDashedLayer.lineDashPattern = NSExpression(forConstantValue: AnchorStyleMetrics.standardDashPattern)
      anchorRadiusStrokeDashedLayer.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.thickLineWidth)
      anchorRadiusStrokeDashedLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.hiddenOpacity)
      insertLayer(anchorRadiusStrokeDashedLayer, identifier: .anchorRadiusStrokeDashed, into: style)

      let anchorRadiusStrokeSolidLayer = MLNLineStyleLayer(identifier: MapLayerIdentifier.anchorRadiusStrokeSolid.rawValue, source: anchorRadiusSource)
      anchorRadiusStrokeSolidLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.anchorArmed))
      anchorRadiusStrokeSolidLayer.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.standardLineWidth)
      anchorRadiusStrokeSolidLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.hiddenOpacity)
      insertLayer(anchorRadiusStrokeSolidLayer, identifier: .anchorRadiusStrokeSolid, into: style)

      let anchorEvitementSource = MLNShapeSource(identifier: MapSourceIdentifier.anchorEvitement.rawValue, shape: nil, options: nil)
      style.addSource(anchorEvitementSource)

      let anchorEvitementLayer = MLNLineStyleLayer(identifier: MapLayerIdentifier.anchorEvitementLine.rawValue, source: anchorEvitementSource)
      anchorEvitementLayer.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.thickLineWidth)
      anchorEvitementLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.anchorArmed))
      anchorEvitementLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.evitementDefaultOpacity)
      insertLayer(anchorEvitementLayer, identifier: .anchorEvitementLine, into: style)


      let anchorRodeSource = MLNShapeSource(identifier: MapSourceIdentifier.anchorRode.rawValue, shape: nil, options: nil)
      style.addSource(anchorRodeSource)

      let anchorRodeLayer = MLNLineStyleLayer(identifier: MapLayerIdentifier.anchorRodeLine.rawValue, source: anchorRodeSource)
      anchorRodeLayer.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.standardLineWidth)
      anchorRodeLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.anchorDropped))
      anchorRodeLayer.lineDashPattern = NSExpression(forConstantValue: AnchorStyleMetrics.standardDashPattern)
      anchorRodeLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.rodeDefaultOpacity)
      insertLayer(anchorRodeLayer, identifier: .anchorRodeLine, into: style)

      let anchorPointSource = MLNShapeSource(identifier: MapSourceIdentifier.anchorPoint.rawValue, shape: nil, options: nil)
      style.addSource(anchorPointSource)

      let anchorPointLayer = MLNSymbolStyleLayer(identifier: MapLayerIdentifier.anchorPoint.rawValue, source: anchorPointSource)
      anchorPointLayer.iconImageName = NSExpression(forConstantValue: "anchor-icon-dropped")
      anchorPointLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      anchorPointLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      anchorPointLayer.iconAnchor = NSExpression(forConstantValue: "center")
      anchorPointLayer.iconScale = NSExpression(forConstantValue: 1.0)
      anchorPointLayer.iconOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.visibleOpacity)
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
  static func updateVisibleWaypoints(states: [WaypointVisualState], targetWaypointID: String? = nil, in style: MLNStyle, theme: MarineTheme) {
    ensureNavigationLayersExist(in: style, theme: theme)
    if let source = style.source(withIdentifier: MapSourceIdentifier.visibleWaypoints.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createVisibleWaypointsFeature(from: states, targetWaypointID: targetWaypointID)
    }
  }

  /// Updates target GoTo waypoint on the MapLibre style.
  static func updateGoToWaypoint(state: WaypointVisualState?, targetWaypointID: String? = nil, in style: MLNStyle, theme: MarineTheme) {
    ensureNavigationLayersExist(in: style, theme: theme)
    if let source = style.source(withIdentifier: MapSourceIdentifier.goToWaypoint.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createGoToWaypointFeature(from: state, targetWaypointID: targetWaypointID)
    }
  }

  /// Updates bearing line feature on the MapLibre style.
  static func updateBearingLine(state: BearingLineVisualState?, in style: MLNStyle, theme: MarineTheme) {
    ensureNavigationLayersExist(in: style, theme: theme)
    if let source = style.source(withIdentifier: MapSourceIdentifier.bearingLine.rawValue) as? MLNShapeSource {
      source.shape = MapLibreFeatureFactory.createBearingLineFeature(from: state)
    }
  }

  /// Updates 2-point measurement line feature on the MapLibre style.
  static func updateMeasureLine(state: MeasureState, in style: MLNStyle, theme: MarineTheme) {
    ensureNavigationLayersExist(in: style, theme: theme)
    guard let lineSource = style.source(withIdentifier: MapSourceIdentifier.measureLine.rawValue) as? MLNShapeSource else { return }
    switch state {
    case .inactive:
      lineSource.shape = nil
    case .active(let start, let end):
      var coordinates = [start, end]
      let lineFeature = MLNPolylineFeature(coordinates: &coordinates, count: 2)
      lineSource.shape = lineFeature
    }
  }

  /// Updates 2-point measurement pin features (Pins A and B) on the MapLibre style.
  static func updateMeasurePins(
    state: MeasureState,
    activePin: ActiveMeasurePin,
    in style: MLNStyle,
    theme: MarineTheme
  ) {
    ensureNavigationLayersExist(in: style, theme: theme)
    guard let pinSource = style.source(withIdentifier: MapSourceIdentifier.measurePins.rawValue) as? MLNShapeSource else { return }

    switch state {
    case .inactive:
      pinSource.shape = nil
    case .active(let start, let end):
      let featureA = MLNPointFeature()
      featureA.coordinate = start
      featureA.attributes = [
        "id": "A",
        "icon": activePin == .start ? "measure-pin-a-selected" : "measure-pin-a-idle",
        "sortKey": activePin == .start ? 2 : 1
      ]

      let featureB = MLNPointFeature()
      featureB.coordinate = end
      featureB.attributes = [
        "id": "B",
        "icon": activePin == .end ? "measure-pin-b-selected" : "measure-pin-b-idle",
        "sortKey": activePin == .end ? 2 : 1
      ]

      pinSource.shape = MLNShapeCollectionFeature(shapes: [featureA, featureB])
    }
  }

  /// Updates contextual target pin feature on the MapLibre style with zero GPU/Metal latency.
  static func updateTargetPin(
    coordinate: CLLocationCoordinate2D?,
    isDragging: Bool,
    isVisible: Bool,
    in style: MLNStyle,
    theme: MarineTheme
  ) {
    ensureNavigationLayersExist(in: style, theme: theme)
    guard let pinSource = style.source(withIdentifier: MapSourceIdentifier.targetPin.rawValue) as? MLNShapeSource else { return }

    guard isVisible, let coord = coordinate else {
      pinSource.shape = nil
      return
    }

    let feature = MLNPointFeature()
    feature.coordinate = coord
    feature.attributes = [
      "icon": isDragging ? "target-pin-dragging" : "target-pin-idle"
    ]
    pinSource.shape = feature
  }

  /// Updates anchor features and layer styling on the MapLibre style.
  static func updateAnchor(state: AnchorVisualState?, in style: MLNStyle, theme: MarineTheme) {
    ensureNavigationLayersExist(in: style, theme: theme)
    let anchorFeatures = MapLibreFeatureFactory.createAnchorFeatures(from: state)
    if let source = style.source(withIdentifier: MapSourceIdentifier.anchorRadius.rawValue) as? MLNShapeSource {
      source.shape = anchorFeatures.radiusFeature
    }
    if let source = style.source(withIdentifier: MapSourceIdentifier.anchorEvitement.rawValue) as? MLNShapeSource {
      source.shape = anchorFeatures.evitementLineFeature
    }
    if let source = style.source(withIdentifier: MapSourceIdentifier.anchorRode.rawValue) as? MLNShapeSource {
      source.shape = anchorFeatures.rodeLineFeature
    }
    if let source = style.source(withIdentifier: MapSourceIdentifier.anchorPoint.rawValue) as? MLNShapeSource {
      source.shape = anchorFeatures.pointFeature
    }
    if let status = state?.status {
      updateAnchorLayerStyles(in: style, for: status, with: theme)
    }
  }

  /// Updates fill and stroke styles for the anchor radius, rode line, and point layers based on status.
  private static func updateAnchorLayerStyles(in style: MLNStyle, for status: AnchorVisualStatus, with theme: MarineTheme) {
    if let pointLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorPoint.rawValue) as? MLNSymbolStyleLayer {
      pointLayer.iconImageName = NSExpression(forConstantValue: "anchor-icon-\(status.rawValue)")
    }

    guard let fillLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorRadiusFill.rawValue) as? MLNFillStyleLayer,
          let dashedLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorRadiusStrokeDashed.rawValue) as? MLNLineStyleLayer,
          let solidLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorRadiusStrokeSolid.rawValue) as? MLNLineStyleLayer,
          let rodeLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorRodeLine.rawValue) as? MLNLineStyleLayer else {
      return
    }

    let evitementLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorEvitementLine.rawValue) as? MLNLineStyleLayer

    let statusColor: UIColor
    switch status {
    case .setup:
      statusColor = UIColor(theme.colors.anchorDropped).withAlphaComponent(AnchorStyleMetrics.setupColorAlpha)
    case .dropped:
      statusColor = UIColor(theme.colors.anchorDropped)
    case .armed:
      statusColor = UIColor(theme.colors.anchorArmed)
    case .dragging:
      statusColor = UIColor(theme.colors.anchorDragging)
    }

    switch status {
    case .setup:
      fillLayer.fillColor = NSExpression(forConstantValue: statusColor)
      fillLayer.fillOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.setupFillOpacity)

      dashedLayer.lineColor = NSExpression(forConstantValue: statusColor)
      dashedLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.visibleOpacity)

      solidLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.hiddenOpacity)
      rodeLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.hiddenOpacity)
      evitementLayer?.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.hiddenOpacity)

    case .dropped:
      fillLayer.fillColor = NSExpression(forConstantValue: statusColor)
      fillLayer.fillOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.hiddenOpacity)

      dashedLayer.lineColor = NSExpression(forConstantValue: statusColor)
      dashedLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.visibleOpacity)

      solidLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.hiddenOpacity)

      rodeLayer.lineColor = NSExpression(forConstantValue: statusColor)
      rodeLayer.lineDashPattern = NSExpression(forConstantValue: AnchorStyleMetrics.standardDashPattern)
      rodeLayer.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.standardLineWidth)
      rodeLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.rodeDefaultOpacity)

      evitementLayer?.lineColor = NSExpression(forConstantValue: statusColor)
      evitementLayer?.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.thickLineWidth)
      evitementLayer?.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.evitementDefaultOpacity)

    case .armed:
      fillLayer.fillColor = NSExpression(forConstantValue: statusColor)
      fillLayer.fillOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.armedFillOpacity)

      dashedLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.hiddenOpacity)

      solidLayer.lineColor = NSExpression(forConstantValue: statusColor)
      solidLayer.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.standardLineWidth)
      solidLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.solidArmedOpacity)

      rodeLayer.lineColor = NSExpression(forConstantValue: statusColor)
      rodeLayer.lineDashPattern = NSExpression(forConstantValue: AnchorStyleMetrics.armedRodeDashPattern)
      rodeLayer.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.standardLineWidth)
      rodeLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.rodeArmedOpacity)

      evitementLayer?.lineColor = NSExpression(forConstantValue: statusColor)
      evitementLayer?.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.thickLineWidth)
      evitementLayer?.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.evitementDefaultOpacity)

    case .dragging:
      fillLayer.fillColor = NSExpression(forConstantValue: statusColor)
      fillLayer.fillOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.draggingFillOpacity)

      dashedLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.hiddenOpacity)

      solidLayer.lineColor = NSExpression(forConstantValue: statusColor)
      solidLayer.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.draggingLineWidth)
      solidLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.visibleOpacity)

      rodeLayer.lineColor = NSExpression(forConstantValue: statusColor)
      rodeLayer.lineDashPattern = nil
      rodeLayer.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.draggingLineWidth)
      rodeLayer.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.rodeDraggingOpacity)

      evitementLayer?.lineColor = NSExpression(forConstantValue: statusColor)
      evitementLayer?.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.draggingLineWidth)
      evitementLayer?.lineOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.evitementDraggingOpacity)
    }
  }

}

// MARK: - Anchor Style Metrics
private enum AnchorStyleMetrics {
  static let standardLineWidth: CGFloat = 2.0
  static let thickLineWidth: CGFloat = 2.5
  static let draggingLineWidth: CGFloat = 3.0

  static let standardDashPattern: [NSNumber] = [4.0, 4.0]
  static let armedRodeDashPattern: [NSNumber] = [6.0, 3.0]

  static let hiddenOpacity: Double = 0.0
  static let setupFillOpacity: Double = 0.05
  static let armedFillOpacity: Double = 0.10
  static let draggingFillOpacity: Double = 0.25
  static let setupColorAlpha: Double = 0.6

  static let rodeDefaultOpacity: Double = 0.8
  static let rodeArmedOpacity: Double = 0.9
  static let rodeDraggingOpacity: Double = 1.0

  static let evitementDefaultOpacity: Double = 0.70
  static let evitementDraggingOpacity: Double = 0.90

  static let visibleOpacity: Double = 1.0
  static let solidArmedOpacity: Double = 0.9
}

