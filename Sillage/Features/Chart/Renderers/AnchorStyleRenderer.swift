//
//  AnchorStyleRenderer.swift
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

/// Styling constants for anchor watch layers across status transitions.
enum AnchorStyleMetrics {
  static let standardLineWidth: Double = 2.0
  static let thickLineWidth: Double = 2.5
  static let draggingLineWidth: Double = 3.0

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

  static let swingDefaultOpacity: Double = 0.70
  static let swingDraggingOpacity: Double = 0.90

  static let visibleOpacity: Double = 1.0
  static let solidArmedOpacity: Double = 0.9
}

/// Manages the 5 anchor watch layers (radius fill, dashed/solid strokes, swing trail, rode line, anchor symbol).
/// Theme-dependent colors, widths, opacities, and sprite names are driven by GeoJSON `status` match expressions
/// configured inside `applyTheme`, ensuring theme switches never clobber active `.armed` or `.dragging` alarm states.
@MainActor
enum AnchorStyleRenderer {

  static func ensureLayers(in style: MLNStyle) {
    let radiusSource = MapStyleStack.ensureShapeSource(.anchorRadius, in: style)

    if style.layer(withIdentifier: MapLayerIdentifier.anchorRadiusFill.rawValue) == nil {
      let layer = MLNFillStyleLayer(identifier: MapLayerIdentifier.anchorRadiusFill.rawValue, source: radiusSource)
      MapStyleStack.insertLayer(layer, identifier: .anchorRadiusFill, into: style)
    }

    if style.layer(withIdentifier: MapLayerIdentifier.anchorRadiusStrokeDashed.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.anchorRadiusStrokeDashed.rawValue, source: radiusSource)
      layer.lineDashPattern = NSExpression(forConstantValue: AnchorStyleMetrics.standardDashPattern)
      layer.lineWidth = NSExpression(forConstantValue: AnchorStyleMetrics.thickLineWidth)
      MapStyleStack.insertLayer(layer, identifier: .anchorRadiusStrokeDashed, into: style)
    }

    if style.layer(withIdentifier: MapLayerIdentifier.anchorRadiusStrokeSolid.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.anchorRadiusStrokeSolid.rawValue, source: radiusSource)
      MapStyleStack.insertLayer(layer, identifier: .anchorRadiusStrokeSolid, into: style)
    }

    let swingSource = MapStyleStack.ensureShapeSource(.anchorSwing, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.anchorSwingLine.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.anchorSwingLine.rawValue, source: swingSource)
      MapStyleStack.insertLayer(layer, identifier: .anchorSwingLine, into: style)
    }

    let rodeSource = MapStyleStack.ensureShapeSource(.anchorRode, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.anchorRodeLine.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.anchorRodeLine.rawValue, source: rodeSource)
      layer.lineDashPattern = NSExpression(forConstantValue: AnchorStyleMetrics.standardDashPattern)
      MapStyleStack.insertLayer(layer, identifier: .anchorRodeLine, into: style)
    }

    let pointSource = MapStyleStack.ensureShapeSource(.anchorPoint, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.anchorPoint.rawValue) == nil {
      let layer = MLNSymbolStyleLayer(identifier: MapLayerIdentifier.anchorPoint.rawValue, source: pointSource)
      layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      layer.iconAnchor = NSExpression(forConstantValue: "center")
      layer.iconScale = NSExpression(forConstantValue: 1.0)
      layer.iconOpacity = NSExpression(forConstantValue: AnchorStyleMetrics.visibleOpacity)
      MapStyleStack.insertLayer(layer, identifier: .anchorPoint, into: style)
    }
  }

  static func applyTheme(_ theme: MarineTheme, in style: MLNStyle) {
    // Register all 4 status sprite icons once per style load / theme switch
    for status in [AnchorVisualStatus.setup, .dropped, .armed, .dragging] {
      let imageName = MapSpriteIdentifier.anchorIcon(for: status)
      if let image = AnchorGraphicsFactory.createAnchorImage(for: status, theme: theme) {
        style.setImage(image, forName: imageName)
        Logger.mapStyle.debug("Registered anchor icon \(imageName, privacy: .public)")
      }
    }

    let expressions = buildStyleExpressions(for: theme)

    if let pointLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorPoint.rawValue) as? MLNSymbolStyleLayer {
      pointLayer.iconImageName = expressions.pointIconImageName
    }

    if let fillLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorRadiusFill.rawValue) as? MLNFillStyleLayer {
      fillLayer.fillColor = expressions.fillColor
      fillLayer.fillOpacity = expressions.fillOpacity
    }

    if let dashedLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorRadiusStrokeDashed.rawValue) as? MLNLineStyleLayer {
      dashedLayer.lineColor = expressions.dashedStrokeColor
      dashedLayer.lineOpacity = expressions.dashedStrokeOpacity
    }

    if let solidLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorRadiusStrokeSolid.rawValue) as? MLNLineStyleLayer {
      solidLayer.lineColor = expressions.solidStrokeColor
      solidLayer.lineWidth = expressions.solidStrokeWidth
      solidLayer.lineOpacity = expressions.solidStrokeOpacity
    }

    if let rodeLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorRodeLine.rawValue) as? MLNLineStyleLayer {
      rodeLayer.lineColor = expressions.rodeLineColor
      rodeLayer.lineWidth = expressions.rodeLineWidth
      rodeLayer.lineOpacity = expressions.rodeLineOpacity
    }

    if let swingLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorSwingLine.rawValue) as? MLNLineStyleLayer {
      swingLayer.lineColor = expressions.swingLineColor
      swingLayer.lineWidth = expressions.swingLineWidth
      swingLayer.lineOpacity = expressions.swingLineOpacity
    }
  }

  static func updateAnchor(state: AnchorVisualState?, in style: MLNStyle) {
    let features = MapLibreFeatureFactory.createAnchorFeatures(from: state)

    if let radiusSource = style.source(withIdentifier: MapSourceIdentifier.anchorRadius.rawValue) as? MLNShapeSource {
      radiusSource.shape = features.radiusFeature
    }
    if let swingSource = style.source(withIdentifier: MapSourceIdentifier.anchorSwing.rawValue) as? MLNShapeSource {
      swingSource.shape = features.swingLineFeature
    }
    if let rodeSource = style.source(withIdentifier: MapSourceIdentifier.anchorRode.rawValue) as? MLNShapeSource {
      rodeSource.shape = features.rodeLineFeature
    }
    if let pointSource = style.source(withIdentifier: MapSourceIdentifier.anchorPoint.rawValue) as? MLNShapeSource {
      pointSource.shape = features.pointFeature
    }

    // `MLNLineStyleLayer.lineDashPattern` does not support feature-attribute expressions in MapLibre Native;
    // update the non-theme dash pattern structurally when anchor status changes.
    if let status = state?.status,
       let rodeLayer = style.layer(withIdentifier: MapLayerIdentifier.anchorRodeLine.rawValue) as? MLNLineStyleLayer {
      if let pattern = rodeDashPattern(for: status) {
        rodeLayer.lineDashPattern = NSExpression(forConstantValue: pattern)
      } else {
        rodeLayer.lineDashPattern = nil
      }
    }
  }

  // MARK: - Pure Expression & Structural Builders (Testable without MLNStyle)

  struct StyleExpressions {
    let pointIconImageName: NSExpression
    let fillColor: NSExpression
    let fillOpacity: NSExpression
    let dashedStrokeColor: NSExpression
    let dashedStrokeOpacity: NSExpression
    let solidStrokeColor: NSExpression
    let solidStrokeWidth: NSExpression
    let solidStrokeOpacity: NSExpression
    let rodeLineColor: NSExpression
    let rodeLineWidth: NSExpression
    let rodeLineOpacity: NSExpression
    let swingLineColor: NSExpression
    let swingLineWidth: NSExpression
    let swingLineOpacity: NSExpression
  }

  static func rodeDashPattern(for status: AnchorVisualStatus) -> [NSNumber]? {
    switch status {
    case .setup, .dropped:
      return AnchorStyleMetrics.standardDashPattern
    case .armed:
      return AnchorStyleMetrics.armedRodeDashPattern
    case .dragging:
      return nil
    }
  }

  static func buildStyleExpressions(for theme: MarineTheme) -> StyleExpressions {
    let setupColor = UIColor(theme.colors.anchorDropped).withAlphaComponent(AnchorStyleMetrics.setupColorAlpha)
    let droppedColor = UIColor(theme.colors.anchorDropped)
    let armedColor = UIColor(theme.colors.anchorArmed)
    let draggingColor = UIColor(theme.colors.anchorDragging)

    let statusColors: [AnchorVisualStatus: Any] = [
      .setup: setupColor,
      .dropped: droppedColor,
      .armed: armedColor,
      .dragging: draggingColor
    ]

    return StyleExpressions(
      pointIconImageName: statusMatchExpression(
        mapping: [
          .setup: MapSpriteIdentifier.anchorIcon(for: .setup),
          .dropped: MapSpriteIdentifier.anchorIcon(for: .dropped),
          .armed: MapSpriteIdentifier.anchorIcon(for: .armed),
          .dragging: MapSpriteIdentifier.anchorIcon(for: .dragging)
        ],
        defaultValue: MapSpriteIdentifier.anchorIcon(for: .dropped)
      ),
      fillColor: statusMatchExpression(
        mapping: statusColors,
        defaultValue: droppedColor
      ),
      fillOpacity: statusMatchExpression(
        mapping: [
          .setup: AnchorStyleMetrics.setupFillOpacity,
          .dropped: AnchorStyleMetrics.hiddenOpacity,
          .armed: AnchorStyleMetrics.armedFillOpacity,
          .dragging: AnchorStyleMetrics.draggingFillOpacity
        ],
        defaultValue: AnchorStyleMetrics.hiddenOpacity
      ),
      dashedStrokeColor: statusMatchExpression(
        mapping: statusColors,
        defaultValue: droppedColor
      ),
      dashedStrokeOpacity: statusMatchExpression(
        mapping: [
          .setup: AnchorStyleMetrics.visibleOpacity,
          .dropped: AnchorStyleMetrics.visibleOpacity,
          .armed: AnchorStyleMetrics.hiddenOpacity,
          .dragging: AnchorStyleMetrics.hiddenOpacity
        ],
        defaultValue: AnchorStyleMetrics.hiddenOpacity
      ),
      solidStrokeColor: statusMatchExpression(
        mapping: statusColors,
        defaultValue: armedColor
      ),
      solidStrokeWidth: statusMatchExpression(
        mapping: [
          .setup: AnchorStyleMetrics.standardLineWidth,
          .dropped: AnchorStyleMetrics.standardLineWidth,
          .armed: AnchorStyleMetrics.standardLineWidth,
          .dragging: AnchorStyleMetrics.draggingLineWidth
        ],
        defaultValue: AnchorStyleMetrics.standardLineWidth
      ),
      solidStrokeOpacity: statusMatchExpression(
        mapping: [
          .setup: AnchorStyleMetrics.hiddenOpacity,
          .dropped: AnchorStyleMetrics.hiddenOpacity,
          .armed: AnchorStyleMetrics.solidArmedOpacity,
          .dragging: AnchorStyleMetrics.visibleOpacity
        ],
        defaultValue: AnchorStyleMetrics.hiddenOpacity
      ),
      rodeLineColor: statusMatchExpression(
        mapping: statusColors,
        defaultValue: droppedColor
      ),
      rodeLineWidth: statusMatchExpression(
        mapping: [
          .setup: AnchorStyleMetrics.standardLineWidth,
          .dropped: AnchorStyleMetrics.standardLineWidth,
          .armed: AnchorStyleMetrics.standardLineWidth,
          .dragging: AnchorStyleMetrics.draggingLineWidth
        ],
        defaultValue: AnchorStyleMetrics.standardLineWidth
      ),
      rodeLineOpacity: statusMatchExpression(
        mapping: [
          .setup: AnchorStyleMetrics.hiddenOpacity,
          .dropped: AnchorStyleMetrics.rodeDefaultOpacity,
          .armed: AnchorStyleMetrics.rodeArmedOpacity,
          .dragging: AnchorStyleMetrics.rodeDraggingOpacity
        ],
        defaultValue: AnchorStyleMetrics.hiddenOpacity
      ),
      swingLineColor: statusMatchExpression(
        mapping: statusColors,
        defaultValue: armedColor
      ),
      swingLineWidth: statusMatchExpression(
        mapping: [
          .setup: AnchorStyleMetrics.thickLineWidth,
          .dropped: AnchorStyleMetrics.thickLineWidth,
          .armed: AnchorStyleMetrics.thickLineWidth,
          .dragging: AnchorStyleMetrics.draggingLineWidth
        ],
        defaultValue: AnchorStyleMetrics.thickLineWidth
      ),
      swingLineOpacity: statusMatchExpression(
        mapping: [
          .setup: AnchorStyleMetrics.hiddenOpacity,
          .dropped: AnchorStyleMetrics.swingDefaultOpacity,
          .armed: AnchorStyleMetrics.swingDefaultOpacity,
          .dragging: AnchorStyleMetrics.swingDraggingOpacity
        ],
        defaultValue: AnchorStyleMetrics.hiddenOpacity
      )
    )
  }

  static func statusMatchExpression(
    mapping: [AnchorVisualStatus: Any],
    defaultValue: Any
  ) -> NSExpression {
    var dictionary: [NSExpression: NSExpression] = [:]
    for status in [AnchorVisualStatus.setup, .dropped, .armed, .dragging] {
      if let value = mapping[status] {
        dictionary[NSExpression(forConstantValue: status.rawValue)] = NSExpression(forConstantValue: value)
      }
    }
    return NSExpression(
      forMLNMatchingKey: NSExpression(forKeyPath: MapFeatureKey.status.rawValue),
      in: dictionary,
      default: NSExpression(forConstantValue: defaultValue)
    )
  }
}
