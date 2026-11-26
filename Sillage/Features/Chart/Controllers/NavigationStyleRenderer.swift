//
//  NavigationStyleRenderer.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import MapLibre
import SwiftUI
import UIKit

/// Manages nautical navigation layers (active track, saved track, waypoints, GoTo target, bearing line).
@MainActor
enum NavigationStyleRenderer {

  static func ensureLayers(in style: MLNStyle) {
    // 1. Active Track
    let activeTrackSource = MapStyleStack.ensureShapeSource(.activeTrack, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.activeTrack.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.activeTrack.rawValue, source: activeTrackSource)
      layer.lineWidth = NSExpression(forConstantValue: 4.0)
      MapStyleStack.insertLayer(layer, identifier: .activeTrack, into: style)
    }

    // 2. Saved Track
    let savedTrackSource = MapStyleStack.ensureShapeSource(.savedTrack, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.savedTrack.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.savedTrack.rawValue, source: savedTrackSource)
      layer.lineWidth = NSExpression(forConstantValue: 4.0)
      MapStyleStack.insertLayer(layer, identifier: .savedTrack, into: style)
    }

    // 3. Bearing Line (color driven per-feature from target waypoint hex attribute)
    let bearingLineSource = MapStyleStack.ensureShapeSource(.bearingLine, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.bearingLine.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.bearingLine.rawValue, source: bearingLineSource)
      layer.lineWidth = NSExpression(forConstantValue: 1.5)
      layer.lineColor = NSExpression(forKeyPath: MapFeatureKey.color.rawValue)
      layer.lineDashPattern = NSExpression(forConstantValue: [4.0, 4.0])
      MapStyleStack.insertLayer(layer, identifier: .bearingLine, into: style)
    }

    // Align GeoJSON tile quantization with global overzoom ceiling (z22) so waypoint circles stay
    // pixel-locked to the SwiftUI aiming crosshair at extreme zoom levels.
    let waypointSourceOptions: [MLNShapeSourceOption: Any] = [
      .maximumZoomLevel: NSNumber(value: AppConstants.Cartography.Zoom.globalMaximum)
    ]

    // 4. Visible Waypoints
    let visibleWaypointsSource = MapStyleStack.ensureShapeSource(
      .visibleWaypoints,
      options: waypointSourceOptions,
      in: style
    )
    if style.layer(withIdentifier: MapLayerIdentifier.visibleWaypoints.rawValue) == nil {
      let layer = MLNCircleStyleLayer(identifier: MapLayerIdentifier.visibleWaypoints.rawValue, source: visibleWaypointsSource)
      layer.circleRadius = NSExpression(forConstantValue: 6.0)
      layer.circleColor = NSExpression(forKeyPath: MapFeatureKey.color.rawValue)
      layer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
      MapStyleStack.insertLayer(layer, identifier: .visibleWaypoints, into: style)
    }

    // 5. Target GoTo Waypoint
    let goToWaypointSource = MapStyleStack.ensureShapeSource(
      .goToWaypoint,
      options: waypointSourceOptions,
      in: style
    )
    if style.layer(withIdentifier: MapLayerIdentifier.goToWaypoint.rawValue) == nil {
      let layer = MLNCircleStyleLayer(identifier: MapLayerIdentifier.goToWaypoint.rawValue, source: goToWaypointSource)
      layer.circleRadius = NSExpression(forConstantValue: 8.0)
      layer.circleColor = NSExpression(forKeyPath: MapFeatureKey.color.rawValue)
      layer.circleStrokeWidth = NSExpression(forConstantValue: 2.0)
      MapStyleStack.insertLayer(layer, identifier: .goToWaypoint, into: style)
    }
  }

  static func applyTheme(_ theme: MarineTheme, in style: MLNStyle) {
    let haloColor = UIColor(theme.colors.chartSymbolHalo)

    if let activeTrackLayer = style.layer(withIdentifier: MapLayerIdentifier.activeTrack.rawValue) as? MLNLineStyleLayer {
      activeTrackLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.trackActive))
    }

    if let savedTrackLayer = style.layer(withIdentifier: MapLayerIdentifier.savedTrack.rawValue) as? MLNLineStyleLayer {
      savedTrackLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.trackSaved))
    }

    if let visibleWaypointsLayer = style.layer(withIdentifier: MapLayerIdentifier.visibleWaypoints.rawValue) as? MLNCircleStyleLayer {
      visibleWaypointsLayer.circleStrokeColor = NSExpression(forConstantValue: haloColor)
    }

    if let goToWaypointLayer = style.layer(withIdentifier: MapLayerIdentifier.goToWaypoint.rawValue) as? MLNCircleStyleLayer {
      goToWaypointLayer.circleStrokeColor = NSExpression(forConstantValue: haloColor)
    }
  }

  static func updateActiveTrack(points: ArraySlice<TrackPoint>, in style: MLNStyle) {
    guard let source = style.source(withIdentifier: MapSourceIdentifier.activeTrack.rawValue) as? MLNShapeSource else {
      return
    }
    source.shape = MapLibreFeatureFactory.createActiveTrackFeature(from: points)
  }

  static func updateSavedTrack(state: SavedTrackVisualState?, in style: MLNStyle) {
    guard let source = style.source(withIdentifier: MapSourceIdentifier.savedTrack.rawValue) as? MLNShapeSource else {
      return
    }
    source.shape = MapLibreFeatureFactory.createSavedTrackFeature(from: state)
  }

  static func updateVisibleWaypoints(states: [WaypointVisualState], in style: MLNStyle) {
    guard let source = style.source(withIdentifier: MapSourceIdentifier.visibleWaypoints.rawValue) as? MLNShapeSource else {
      return
    }
    source.shape = MapLibreFeatureFactory.createVisibleWaypointsFeature(from: states)
  }

  static func updateGoToWaypoint(state: WaypointVisualState?, in style: MLNStyle) {
    guard let source = style.source(withIdentifier: MapSourceIdentifier.goToWaypoint.rawValue) as? MLNShapeSource else {
      return
    }
    source.shape = MapLibreFeatureFactory.createGoToWaypointFeature(from: state)
  }

  static func updateBearingLine(state: BearingLineVisualState?, in style: MLNStyle) {
    guard let source = style.source(withIdentifier: MapSourceIdentifier.bearingLine.rawValue) as? MLNShapeSource else {
      return
    }
    source.shape = MapLibreFeatureFactory.createBearingLineFeature(from: state)
  }
}
