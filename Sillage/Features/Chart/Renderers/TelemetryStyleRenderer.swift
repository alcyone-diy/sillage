//
//  TelemetryStyleRenderer.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import MapLibre
import OSLog
import SwiftUI
import UIKit

/// Manages live vessel telemetry layers (GPS accuracy polygon, COG vector & ticks, vessel cursor).
@MainActor
enum TelemetryStyleRenderer {

  static func ensureLayers(in style: MLNStyle) {
    // 1. GPS Accuracy Polygon
    let gpsSource = MapStyleStack.ensureShapeSource(.gpsAccuracy, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.gpsAccuracyFill.rawValue) == nil {
      let layer = MLNFillStyleLayer(identifier: MapLayerIdentifier.gpsAccuracyFill.rawValue, source: gpsSource)
      layer.fillOpacity = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyFillOpacity)
      MapStyleStack.insertLayer(layer, identifier: .gpsAccuracyFill, into: style)
    }
    if style.layer(withIdentifier: MapLayerIdentifier.gpsAccuracyStroke.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.gpsAccuracyStroke.rawValue, source: gpsSource)
      layer.lineOpacity = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyStrokeOpacity)
      layer.lineWidth = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyLineWidth)
      MapStyleStack.insertLayer(layer, identifier: .gpsAccuracyStroke, into: style)
    }

    // 2. Heading / COG Vector & Distance Ticks
    let headingSource = MapStyleStack.ensureShapeSource(.heading, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.headingLine.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.headingLine.rawValue, source: headingSource)
      layer.predicate = NSPredicate(format: "%K == %@", MapFeatureKey.type.rawValue, MapFeatureType.vectorLine.rawValue)
      layer.lineWidth = NSExpression(forConstantValue: MarineTheme.ChartMetrics.headingLineWidth)
      MapStyleStack.insertLayer(layer, identifier: .headingLine, into: style)
    }
    if style.layer(withIdentifier: MapLayerIdentifier.headingTick.rawValue) == nil {
      let layer = MLNCircleStyleLayer(identifier: MapLayerIdentifier.headingTick.rawValue, source: headingSource)
      layer.predicate = NSPredicate(format: "%K == %@", MapFeatureKey.type.rawValue, MapFeatureType.vectorTick.rawValue)
      layer.circleRadius = headingTickRadiusExpression()
      layer.circleStrokeWidth = NSExpression(forConstantValue: 1.0)
      MapStyleStack.insertLayer(layer, identifier: .headingTick, into: style)
    }

    // 3. Vessel Symbol Cursor
    let vesselSource = MapStyleStack.ensureShapeSource(.vessel, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.vesselSymbol.rawValue) == nil {
      let layer = MLNSymbolStyleLayer(identifier: MapLayerIdentifier.vesselSymbol.rawValue, source: vesselSource)
      layer.iconImageName = NSExpression(forConstantValue: MapSpriteIdentifier.vesselCursor)
      layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
      layer.iconRotation = vesselIconRotationExpression()
      layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      layer.iconAnchor = NSExpression(forConstantValue: "center")
      // Initialized once at layer creation; `applyTheme` intentionally never writes `iconOpacity`
      // so `updateDataStaleState` owns degraded GPS opacity without risk of theme-switch clobbering.
      layer.iconOpacity = NSExpression(forConstantValue: 1.0)
      MapStyleStack.insertLayer(layer, identifier: .vesselSymbol, into: style)
    }
  }

  static func applyTheme(_ theme: MarineTheme, in style: MLNStyle) {
    let accentColor = UIColor(theme.colors.accent)
    let haloColor = UIColor(theme.colors.chartSymbolHalo)

    if let vesselImage = VesselGraphicsFactory.createVesselImage(
      size: MarineTheme.ChartMetrics.vesselCursorBaseSize,
      color: accentColor,
      strokeColor: haloColor
    ) {
      style.setImage(vesselImage, forName: MapSpriteIdentifier.vesselCursor)
      Logger.mapStyle.debug("Updated vessel cursor sprite image for theme")
    }

    if let gpsFillLayer = style.layer(withIdentifier: MapLayerIdentifier.gpsAccuracyFill.rawValue) as? MLNFillStyleLayer {
      gpsFillLayer.fillColor = NSExpression(forConstantValue: accentColor)
    }

    if let gpsStrokeLayer = style.layer(withIdentifier: MapLayerIdentifier.gpsAccuracyStroke.rawValue) as? MLNLineStyleLayer {
      gpsStrokeLayer.lineColor = NSExpression(forConstantValue: accentColor)
    }

    if let headingLineLayer = style.layer(withIdentifier: MapLayerIdentifier.headingLine.rawValue) as? MLNLineStyleLayer {
      headingLineLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.vectorCOG))
    }

    if let headingTickLayer = style.layer(withIdentifier: MapLayerIdentifier.headingTick.rawValue) as? MLNCircleStyleLayer {
      headingTickLayer.circleColor = NSExpression(forConstantValue: UIColor(theme.colors.vectorTick))
      headingTickLayer.circleStrokeColor = NSExpression(forConstantValue: haloColor)
    }
  }

  static func updateVessel(state: VesselVisualState?, in style: MLNStyle) {
    guard let source = style.source(withIdentifier: MapSourceIdentifier.vessel.rawValue) as? MLNShapeSource else {
      return
    }
    source.shape = MapLibreFeatureFactory.createVesselFeature(from: state)
  }

  static func updateHeadingVector(data: HeadingVectorData?, in style: MLNStyle) {
    guard let source = style.source(withIdentifier: MapSourceIdentifier.heading.rawValue) as? MLNShapeSource else {
      return
    }
    source.shape = MapLibreFeatureFactory.createHeadingVectorFeature(from: data)
  }

  static func updateGpsAccuracy(state: GpsAccuracyVisualState?, in style: MLNStyle) {
    guard let source = style.source(withIdentifier: MapSourceIdentifier.gpsAccuracy.rawValue) as? MLNShapeSource else {
      return
    }
    source.shape = MapLibreFeatureFactory.createAccuracyFeature(from: state)
  }

  static func updateDataStaleState(isStale: Bool, in style: MLNStyle) {
    guard let layer = style.layer(withIdentifier: MapLayerIdentifier.vesselSymbol.rawValue) as? MLNSymbolStyleLayer else {
      return
    }
    layer.iconOpacity = NSExpression(forConstantValue: isStale ? 0.4 : 1.0)
  }

  // MARK: - Pure Expression Builders (Testable without MLNStyle)

  static func headingTickRadiusExpression() -> NSExpression {
    NSExpression(
      forMLNConditional: NSPredicate(format: "%K == YES", MapFeatureKey.isMajorTick.rawValue),
      trueExpression: NSExpression(forConstantValue: 4.0),
      falseExpression: NSExpression(forConstantValue: 2.0)
    )
  }

  static func vesselIconRotationExpression() -> NSExpression {
    NSExpression(
      forMLNConditional: NSPredicate(format: "%K != nil", MapFeatureKey.course.rawValue),
      trueExpression: NSExpression(forKeyPath: MapFeatureKey.course.rawValue),
      falseExpression: NSExpression(forConstantValue: 0.0)
    )
  }
}
