//
//  MapStyleController.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreLocation
import MapLibre

/// Thin stateless `@MainActor` facade coordinating MapLibre style lifecycle, theming, and domain renderers.
@MainActor
enum MapStyleController {

  // MARK: - Style Lifecycle & Theme

  /// Idempotently creates all persistent vector sources and layers in deterministic Z-index order.
  static func ensureAllLayers(in style: MLNStyle) {
    style.performsPlacementTransitions = false
    OfflineZonesStyleRenderer.ensureLayers(in: style)
    TelemetryStyleRenderer.ensureLayers(in: style)
    NavigationStyleRenderer.ensureLayers(in: style)
    ChartToolsStyleRenderer.ensureLayers(in: style)
    AnchorStyleRenderer.ensureLayers(in: style)
  }

  /// Applies `MarineTheme` colors, metrics, data-driven expressions, and GPU sprite images across all renderers.
  /// Safe to invoke on initial style load and on every `MarineTheme` switch without touching `updateDataStaleState`.
  static func applyTheme(_ theme: MarineTheme, in style: MLNStyle) {
    OfflineZonesStyleRenderer.applyTheme(theme, in: style)
    TelemetryStyleRenderer.applyTheme(theme, in: style)
    NavigationStyleRenderer.applyTheme(theme, in: style)
    ChartToolsStyleRenderer.applyTheme(theme, in: style)
    AnchorStyleRenderer.applyTheme(theme, in: style)
  }

  // MARK: - Raster Base & Overlays

  static func updateChartSource(_ source: ChartSource, in style: MLNStyle, isOverlayEnabled: Bool) {
    RasterStyleRenderer.updateChartSource(source, in: style, isOverlayEnabled: isOverlayEnabled)
  }

  static func updateOpenSeaMapOverlay(isEnabled: Bool, in style: MLNStyle) {
    RasterStyleRenderer.updateOpenSeaMapOverlay(isEnabled: isEnabled, in: style)
  }

  // MARK: - Offline Zones

  static func updateOfflineMask(state: OfflineMaskVisualState?, in style: MLNStyle) {
    OfflineZonesStyleRenderer.updateMask(state: state, in: style)
  }

  static func updateOfflineHighlight(region: HighlightedOfflineRegion?, in style: MLNStyle) {
    OfflineZonesStyleRenderer.updateHighlight(region: region, in: style)
  }

  static func updateOfflineSelection(bounds: GeographicBoundingBox?, in style: MLNStyle) {
    OfflineZonesStyleRenderer.updateSelection(bounds: bounds, in: style)
  }

  // MARK: - Vessel Telemetry

  static func updateVessel(state: VesselVisualState?, in style: MLNStyle) {
    TelemetryStyleRenderer.updateVessel(state: state, in: style)
  }

  static func updateHeadingVector(data: HeadingVectorData?, in style: MLNStyle) {
    TelemetryStyleRenderer.updateHeadingVector(data: data, in: style)
  }

  static func updateGpsAccuracy(state: GpsAccuracyVisualState?, in style: MLNStyle) {
    TelemetryStyleRenderer.updateGpsAccuracy(state: state, in: style)
  }

  static func updateDataStaleState(isStale: Bool, in style: MLNStyle) {
    TelemetryStyleRenderer.updateDataStaleState(isStale: isStale, in: style)
  }

  // MARK: - Navigation

  static func updateActiveTrack(points: ArraySlice<TrackPoint>, in style: MLNStyle) {
    NavigationStyleRenderer.updateActiveTrack(points: points, in: style)
  }

  static func updateSavedTrack(state: SavedTrackVisualState?, in style: MLNStyle) {
    NavigationStyleRenderer.updateSavedTrack(state: state, in: style)
  }

  static func updateVisibleWaypoints(states: [WaypointVisualState], in style: MLNStyle) {
    NavigationStyleRenderer.updateVisibleWaypoints(states: states, in: style)
  }

  static func updateGoToWaypoint(state: WaypointVisualState?, in style: MLNStyle) {
    NavigationStyleRenderer.updateGoToWaypoint(state: state, in: style)
  }

  static func updateBearingLine(state: BearingLineVisualState?, in style: MLNStyle) {
    NavigationStyleRenderer.updateBearingLine(state: state, in: style)
  }

  // MARK: - Chart Tools & Anchor Watch

  static func updateMeasureLine(state: MeasureState, in style: MLNStyle) {
    ChartToolsStyleRenderer.updateMeasureLine(state: state, in: style)
  }

  static func updateMeasurePins(state: MeasureState, activePin: ActiveMeasurePin, in style: MLNStyle) {
    ChartToolsStyleRenderer.updateMeasurePins(state: state, activePin: activePin, in: style)
  }

  static func updateTargetAimingCrosshair(coordinate: CLLocationCoordinate2D?, in style: MLNStyle) {
    ChartToolsStyleRenderer.updateTargetAimingCrosshair(coordinate: coordinate, in: style)
  }

  static func updateAnchor(state: AnchorVisualState?, in style: MLNStyle) {
    AnchorStyleRenderer.updateAnchor(state: state, in: style)
  }
}
