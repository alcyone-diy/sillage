//
//  OfflineZonesStyleRenderer.swift
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

/// Manages persistent vector layers for offline map masks, region previews, and active selection bounds.
/// Kept permanently in the style stack (`shape = nil`, `isVisible = false` when idle) so `applyTheme`
/// always styles them ahead of display and Z-index churn is eliminated during 60fps corner dragging.
@MainActor
enum OfflineZonesStyleRenderer {

  static func ensureLayers(in style: MLNStyle) {
    // 1. Offline Mask & Saved Regions Border
    let maskSource = MapStyleStack.ensureShapeSource(.offlineMask, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.offlineMask.rawValue) == nil {
      let layer = MLNFillStyleLayer(identifier: MapLayerIdentifier.offlineMask.rawValue, source: maskSource)
      layer.isVisible = false
      MapStyleStack.insertLayer(layer, identifier: .offlineMask, into: style)
    }

    let borderSource = MapStyleStack.ensureShapeSource(.offlineRegionsBorder, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.offlineRegionsBorder.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.offlineRegionsBorder.rawValue, source: borderSource)
      layer.lineDashPattern = NSExpression(forConstantValue: [4.0, 3.0])
      layer.isVisible = false
      MapStyleStack.insertLayer(layer, identifier: .offlineRegionsBorder, into: style)
    }

    // 2. Highlighted Offline Region Preview
    let highlightSource = MapStyleStack.ensureShapeSource(.offlineHighlight, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.offlineHighlightFill.rawValue) == nil {
      let layer = MLNFillStyleLayer(identifier: MapLayerIdentifier.offlineHighlightFill.rawValue, source: highlightSource)
      layer.isVisible = false
      MapStyleStack.insertLayer(layer, identifier: .offlineHighlightFill, into: style)
    }
    if style.layer(withIdentifier: MapLayerIdentifier.offlineHighlightBorder.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.offlineHighlightBorder.rawValue, source: highlightSource)
      layer.lineDashPattern = NSExpression(forConstantValue: [6.0, 3.0])
      layer.isVisible = false
      MapStyleStack.insertLayer(layer, identifier: .offlineHighlightBorder, into: style)
    }

    // 3. Active Offline Selection Box & Draggable Corner Handles
    let selectionSource = MapStyleStack.ensureShapeSource(.offlineSelection, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.offlineSelectionFill.rawValue) == nil {
      let layer = MLNFillStyleLayer(identifier: MapLayerIdentifier.offlineSelectionFill.rawValue, source: selectionSource)
      layer.isVisible = false
      MapStyleStack.insertLayer(layer, identifier: .offlineSelectionFill, into: style)
    }
    if style.layer(withIdentifier: MapLayerIdentifier.offlineSelectionBorder.rawValue) == nil {
      let layer = MLNLineStyleLayer(identifier: MapLayerIdentifier.offlineSelectionBorder.rawValue, source: selectionSource)
      layer.isVisible = false
      MapStyleStack.insertLayer(layer, identifier: .offlineSelectionBorder, into: style)
    }

    let cornersSource = MapStyleStack.ensureShapeSource(.offlineSelectionCorners, in: style)
    if style.layer(withIdentifier: MapLayerIdentifier.offlineSelectionCorners.rawValue) == nil {
      let layer = MLNCircleStyleLayer(identifier: MapLayerIdentifier.offlineSelectionCorners.rawValue, source: cornersSource)
      layer.isVisible = false
      MapStyleStack.insertLayer(layer, identifier: .offlineSelectionCorners, into: style)
    }
  }

  static func applyTheme(_ theme: MarineTheme, in style: MLNStyle) {
    let accentColor = UIColor(theme.colors.accent)

    if let maskLayer = style.layer(withIdentifier: MapLayerIdentifier.offlineMask.rawValue) as? MLNFillStyleLayer {
      maskLayer.fillColor = NSExpression(forConstantValue: UIColor(theme.colors.overlay))
      maskLayer.fillOpacity = NSExpression(forConstantValue: MarineTheme.ChartMetrics.offlineMaskFillOpacity)
    }

    if let borderLayer = style.layer(withIdentifier: MapLayerIdentifier.offlineRegionsBorder.rawValue) as? MLNLineStyleLayer {
      borderLayer.lineColor = NSExpression(forConstantValue: accentColor)
      borderLayer.lineWidth = NSExpression(forConstantValue: MarineTheme.ChartMetrics.offlineRegionsBorderLineWidth)
      borderLayer.lineOpacity = NSExpression(forConstantValue: MarineTheme.ChartMetrics.offlineRegionsBorderOpacity)
    }

    if let highlightFill = style.layer(withIdentifier: MapLayerIdentifier.offlineHighlightFill.rawValue) as? MLNFillStyleLayer {
      highlightFill.fillColor = NSExpression(forConstantValue: accentColor)
      highlightFill.fillOpacity = NSExpression(forConstantValue: 0.12)
    }

    if let highlightBorder = style.layer(withIdentifier: MapLayerIdentifier.offlineHighlightBorder.rawValue) as? MLNLineStyleLayer {
      highlightBorder.lineColor = NSExpression(forConstantValue: accentColor)
      highlightBorder.lineWidth = NSExpression(forConstantValue: 2.5)
      highlightBorder.lineOpacity = NSExpression(forConstantValue: 0.9)
    }

    if let selectionFill = style.layer(withIdentifier: MapLayerIdentifier.offlineSelectionFill.rawValue) as? MLNFillStyleLayer {
      selectionFill.fillColor = NSExpression(forConstantValue: accentColor)
      selectionFill.fillOpacity = NSExpression(forConstantValue: 0.12)
    }

    if let selectionBorder = style.layer(withIdentifier: MapLayerIdentifier.offlineSelectionBorder.rawValue) as? MLNLineStyleLayer {
      selectionBorder.lineColor = NSExpression(forConstantValue: accentColor)
      selectionBorder.lineWidth = NSExpression(forConstantValue: Double(MarineTheme.Metrics.borderWidth * 2.5))
      selectionBorder.lineOpacity = NSExpression(forConstantValue: 1.0)
    }

    if let cornersLayer = style.layer(withIdentifier: MapLayerIdentifier.offlineSelectionCorners.rawValue) as? MLNCircleStyleLayer {
      cornersLayer.circleRadius = NSExpression(forConstantValue: theme.isGloveMode ? 14.0 : 10.0)
      cornersLayer.circleColor = NSExpression(forConstantValue: accentColor)
      cornersLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor(theme.colors.panelBackground))
      cornersLayer.circleStrokeWidth = NSExpression(forConstantValue: MarineTheme.Metrics.borderWidth * 2.0)
    }
  }

  static func updateMask(state: OfflineMaskVisualState?, in style: MLNStyle) {
    guard let maskSource = style.source(withIdentifier: MapSourceIdentifier.offlineMask.rawValue) as? MLNShapeSource,
          let borderSource = style.source(withIdentifier: MapSourceIdentifier.offlineRegionsBorder.rawValue) as? MLNShapeSource else {
      return
    }
    let maskLayer = style.layer(withIdentifier: MapLayerIdentifier.offlineMask.rawValue)
    let borderLayer = style.layer(withIdentifier: MapLayerIdentifier.offlineRegionsBorder.rawValue)

    if let state, state.isActive {
      maskSource.shape = MapLibreFeatureFactory.createOfflineMaskFeature(from: state)
      borderSource.shape = MapLibreFeatureFactory.createOfflineRegionsBorderFeature(from: state)
      maskLayer?.isVisible = true
      borderLayer?.isVisible = true
    } else {
      maskLayer?.isVisible = false
      borderLayer?.isVisible = false
      maskSource.shape = nil
      borderSource.shape = nil
    }
  }

  static func updateHighlight(region: HighlightedOfflineRegion?, in style: MLNStyle) {
    guard let source = style.source(withIdentifier: MapSourceIdentifier.offlineHighlight.rawValue) as? MLNShapeSource else {
      return
    }
    let fillLayer = style.layer(withIdentifier: MapLayerIdentifier.offlineHighlightFill.rawValue)
    let borderLayer = style.layer(withIdentifier: MapLayerIdentifier.offlineHighlightBorder.rawValue)

    if let region {
      source.shape = MapLibreFeatureFactory.createOfflineHighlightFeature(from: region.bounds)
      fillLayer?.isVisible = true
      borderLayer?.isVisible = true
    } else {
      fillLayer?.isVisible = false
      borderLayer?.isVisible = false
      source.shape = nil
    }
  }

  static func updateSelection(bounds: GeographicBoundingBox?, in style: MLNStyle) {
    guard let selectionSource = style.source(withIdentifier: MapSourceIdentifier.offlineSelection.rawValue) as? MLNShapeSource,
          let cornersSource = style.source(withIdentifier: MapSourceIdentifier.offlineSelectionCorners.rawValue) as? MLNShapeSource else {
      return
    }
    let fillLayer = style.layer(withIdentifier: MapLayerIdentifier.offlineSelectionFill.rawValue)
    let borderLayer = style.layer(withIdentifier: MapLayerIdentifier.offlineSelectionBorder.rawValue)
    let cornersLayer = style.layer(withIdentifier: MapLayerIdentifier.offlineSelectionCorners.rawValue)

    if let bounds {
      selectionSource.shape = MapLibreFeatureFactory.createOfflineSelectionFeature(from: bounds)
      cornersSource.shape = MapLibreFeatureFactory.createOfflineSelectionCornersFeature(from: bounds)
      fillLayer?.isVisible = true
      borderLayer?.isVisible = true
      cornersLayer?.isVisible = true
    } else {
      fillLayer?.isVisible = false
      borderLayer?.isVisible = false
      cornersLayer?.isVisible = false
      selectionSource.shape = nil
      cornersSource.shape = nil
    }
  }
}
