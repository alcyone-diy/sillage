//
//  ChartToolsStyleRenderer.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreLocation
import MapLibre
import OSLog
import SwiftUI
import UIKit

/// Manages interactive chart tool layers (2-point measure ruler/pins and GPU aiming crosshair).
@MainActor
enum ChartToolsStyleRenderer {

  static func ensureLayers(in style: MLNStyle) {
    // 1. Measure Line
    let measureLineSource = MapStyleStack.ensureShapeSource(.measureLine, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.measureLine.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.measureLine.rawValue, source: measureLineSource)
      layer.lineWidth = NSExpression(forConstantValue: 2.5)
      layer.lineDashPattern = NSExpression(forConstantValue: [4.0, 4.0])
      MapStyleStack.insertLayer(layer, identifier: .measureLine, into: style)
    }

    // 2. Measure Pins A & B (positioned above waypoints and vessel)
    let measurePinsSource = MapStyleStack.ensureShapeSource(.measurePins, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.measurePins.rawValue) == nil {
      let layer = MLNSymbolStyleLayer(identifier: MapLayerIdentifier.measurePins.rawValue, source: measurePinsSource)
      layer.iconImageName = NSExpression(forKeyPath: MapFeatureKey.icon.rawValue)
      layer.iconAnchor = NSExpression(forConstantValue: "top")
      layer.iconOffset = NSExpression(forConstantValue: [0.0, -MarinePinGraphicsFactory.focalPointY])
      layer.iconRotationAlignment = NSExpression(forConstantValue: "viewport")
      layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      layer.symbolSortKey = NSExpression(forKeyPath: MapFeatureKey.sortKey.rawValue)
      layer.iconOpacity = NSExpression(forConstantValue: 1.0)
      layer.iconOpacityTransition = MLNTransition(duration: 0, delay: 0)
      MapStyleStack.insertLayer(layer, identifier: .measurePins, into: style)
    }

    // 3. Target Aiming Crosshair (GPU layer used during camera centering flights)
    let crosshairSource = MapStyleStack.ensureShapeSource(.targetAimingCrosshair, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.targetAimingCrosshair.rawValue) == nil {
      let layer = MLNSymbolStyleLayer(identifier: MapLayerIdentifier.targetAimingCrosshair.rawValue, source: crosshairSource)
      layer.iconImageName = NSExpression(forConstantValue: MapSpriteIdentifier.targetAimingCrosshair)
      layer.iconAnchor = NSExpression(forConstantValue: "center")
      layer.iconRotationAlignment = NSExpression(forConstantValue: "viewport")
      layer.iconOpacityTransition = MLNTransition(duration: 0, delay: 0)
      layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      layer.isVisible = false
      MapStyleStack.insertLayer(layer, identifier: .targetAimingCrosshair, into: style)
    }
  }

  static func applyTheme(_ theme: MarineTheme, in style: MLNStyle) {
    if let measureLineLayer = style.layer(withIdentifier: MapLayerIdentifier.measureLine.rawValue) as? MLNLineStyleLayer {
      measureLineLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.accent))
    }

    // Regenerate and upload the 4 measure pin icons strictly on style load / theme switch
    for pin in [ActiveMeasurePin.start, .end] {
      for isSelected in [true, false] {
        let imageName = MapSpriteIdentifier.measurePinIcon(for: pin, isSelected: isSelected)
        if let image = MarinePinGraphicsFactory.createMeasurePinImage(for: pin, isSelected: isSelected, theme: theme) {
          style.setImage(image, forName: imageName)
          Logger.mapStyle.debug("Registered measure pin icon \(imageName, privacy: .public)")
        }
      }
    }

    // Regenerate target aiming crosshair sprite from SwiftUI view
    let crosshairView = MarineCrosshairView.targetAiming(theme: theme)
      .padding(8)
      .environment(\.marineTheme, theme)
    let renderer = ImageRenderer(content: crosshairView)
    renderer.scale = UIScreen.main.scale
    if let image = renderer.uiImage {
      style.setImage(image, forName: MapSpriteIdentifier.targetAimingCrosshair)
      Logger.mapStyle.debug("Updated target aiming crosshair sprite image for theme")
    }
  }

  static func updateMeasureLine(state: MeasureState, in style: MLNStyle) {
    guard let lineSource = style.source(withIdentifier: MapSourceIdentifier.measureLine.rawValue) as? MLNShapeSource else {
      return
    }
    lineSource.shape = MapLibreFeatureFactory.createMeasureLineFeature(from: state)
  }

  static func updateMeasurePins(
    state: MeasureState,
    activePin: ActiveMeasurePin,
    in style: MLNStyle
  ) {
    guard let pinSource = style.source(withIdentifier: MapSourceIdentifier.measurePins.rawValue) as? MLNShapeSource else {
      return
    }
    pinSource.shape = MapLibreFeatureFactory.createMeasurePinsFeature(from: state, activePin: activePin)
  }

  static func updateTargetAimingCrosshair(coordinate: CLLocationCoordinate2D?, in style: MLNStyle) {
    guard let source = style.source(withIdentifier: MapSourceIdentifier.targetAimingCrosshair.rawValue) as? MLNShapeSource else {
      return
    }
    let layer = style.layer(withIdentifier: MapLayerIdentifier.targetAimingCrosshair.rawValue)
    if let feature = MapLibreFeatureFactory.createTargetAimingCrosshairFeature(from: coordinate) {
      source.shape = feature
      layer?.isVisible = true
    } else {
      // Hide the layer synchronously on the render thread before the async GeoJSON worker clears the shape
      layer?.isVisible = false
      source.shape = nil
    }
  }
}
