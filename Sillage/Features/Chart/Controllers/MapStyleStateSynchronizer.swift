//
//  MapStyleStateSynchronizer.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreLocation
import Foundation
import MapLibre

/// Constant-time O(1) boundary fingerprint of the live recorded track buffer.
/// Intentionally stores ONLY scalar metadata (`count`, `firstTimestamp`, `lastTimestamp`) and NEVER retains
/// `ArraySlice<TrackPoint>`, guaranteeing `TrackRecordingService.trackPoints` remains uniquely referenced (`refcount == 1`)
/// so 1 Hz GPS `append` operations mutate in place without triggering O(n) Copy-on-Write buffer copies.
struct ActiveTrackFingerprint: Equatable, Sendable {
  let count: Int
  let firstTimestamp: Date?
  let lastTimestamp: Date?

  init(count: Int = 0, firstTimestamp: Date? = nil, lastTimestamp: Date? = nil) {
    self.count = count
    self.firstTimestamp = firstTimestamp
    self.lastTimestamp = lastTimestamp
  }

  init(points: ArraySlice<TrackPoint>) {
    self.count = points.count
    self.firstTimestamp = points.first?.timestamp
    self.lastTimestamp = points.last?.timestamp
  }
}

/// Value snapshot of every visual input consumed by `MapStyleController`.
/// High-frequency interactive gesture fields (`offlineSelectionBounds`, `aimingCoordinate`) are `var` internally
/// so `MapStyleStateSynchronizer` fast-paths can align `lastSnapshot` in O(1) without rebuilding the full struct.
struct MapStyleSnapshot: Equatable, Sendable {
  let chartSource: ChartSource?
  let isOpenSeaMapOverlayEnabled: Bool
  let marineTheme: MarineTheme
  let offlineMask: OfflineMaskVisualState?
  let offlineHighlight: HighlightedOfflineRegion?
  var offlineSelectionBounds: GeographicBoundingBox?
  let gpsAccuracy: GpsAccuracyVisualState?
  let savedTrack: SavedTrackVisualState?
  let activeTrack: ActiveTrackFingerprint
  let bearingLine: BearingLineVisualState?
  let measureState: MeasureState
  let measureActivePin: ActiveMeasurePin
  let visibleWaypoints: [WaypointVisualState]
  let goToWaypoint: WaypointVisualState?
  let anchor: AnchorVisualState?
  let headingVector: HeadingVectorData?
  let vessel: VesselVisualState?
  let isDataStale: Bool
  var aimingCoordinate: CLLocationCoordinate2D?
}

/// Bitmask of independent MapLibre style domains requiring synchronization.
struct MapStyleDirtyDomains: OptionSet, Sendable, Equatable {
  let rawValue: UInt32

  /// Persistent vector sources & layers creation (`MapStyleController.ensureAllLayers`).
  static let layerStructure    = MapStyleDirtyDomains(rawValue: 1 << 0)
  /// Base raster chart tiles (`MBTiles`, `GeoGarage`, `OpenSeaMap`).
  static let baseChart         = MapStyleDirtyDomains(rawValue: 1 << 1)
  /// OpenSeaMap seamark raster overlay toggle.
  static let openSeaMapOverlay = MapStyleDirtyDomains(rawValue: 1 << 2)
  /// Theme colors, metrics, expressions, and GPU sprite images (`MapStyleController.applyTheme`).
  static let theme             = MapStyleDirtyDomains(rawValue: 1 << 3)
  /// Offline coverage dimming mask and saved region borders.
  static let offlineMask       = MapStyleDirtyDomains(rawValue: 1 << 4)
  /// Highlighted offline chart preview polygon.
  static let offlineHighlight  = MapStyleDirtyDomains(rawValue: 1 << 5)
  /// Active offline selection rectangle and corner handles.
  static let offlineSelection  = MapStyleDirtyDomains(rawValue: 1 << 6)
  /// GPS horizontal accuracy circle polygon.
  static let gpsAccuracy       = MapStyleDirtyDomains(rawValue: 1 << 7)
  /// Historical displayed saved track polyline(s).
  static let savedTrack        = MapStyleDirtyDomains(rawValue: 1 << 8)
  /// Live recorded track polyline(s).
  static let activeTrack       = MapStyleDirtyDomains(rawValue: 1 << 9)
  /// Navigation GoTo bearing line.
  static let bearingLine       = MapStyleDirtyDomains(rawValue: 1 << 10)
  /// Interactive 2-point measure line and pins A/B.
  static let measure           = MapStyleDirtyDomains(rawValue: 1 << 11)
  /// Visible saved and draft waypoints.
  static let visibleWaypoints  = MapStyleDirtyDomains(rawValue: 1 << 12)
  /// Active GoTo target waypoint circle.
  static let goToWaypoint      = MapStyleDirtyDomains(rawValue: 1 << 13)
  /// Anchor watch radius, swing trail, rode line, and anchor icon.
  static let anchor            = MapStyleDirtyDomains(rawValue: 1 << 14)
  /// Vessel COG/HDG vector line and distance ticks.
  static let headingVector     = MapStyleDirtyDomains(rawValue: 1 << 15)
  /// Vessel position/course symbol feature.
  static let vessel            = MapStyleDirtyDomains(rawValue: 1 << 16)
  /// Degraded / stale telemetry vessel opacity.
  static let dataStale         = MapStyleDirtyDomains(rawValue: 1 << 17)
  /// GPU target aiming crosshair used during long-press and centering flights.
  static let aimingReticle     = MapStyleDirtyDomains(rawValue: 1 << 18)

  static let all: MapStyleDirtyDomains = [
    .layerStructure,
    .baseChart,
    .openSeaMapOverlay,
    .theme,
    .offlineMask,
    .offlineHighlight,
    .offlineSelection,
    .gpsAccuracy,
    .savedTrack,
    .activeTrack,
    .bearingLine,
    .measure,
    .visibleWaypoints,
    .goToWaypoint,
    .anchor,
    .headingVector,
    .vessel,
    .dataStale,
    .aimingReticle
  ]
}

/// Owns the single source-of-truth diff cache between SwiftUI visual state and MapLibre's `MLNStyle`,
/// unifying `MapLibreView.updateUIView` (`forceAll: false`) and `mapView(_:didFinishLoading:)` (`forceAll: true`).
@MainActor
final class MapStyleStateSynchronizer {

  private(set) var lastSnapshot: MapStyleSnapshot?

  // MARK: - Pure Testable Diffing

  /// Compares `newSnapshot` against `lastSnapshot`, stores `newSnapshot`, and returns the exact dirty domains.
  /// Pure state computation free of `MLNMapView` and `MLNStyle` dependencies for deterministic unit testing.
  func computeDirtyDomains(for newSnapshot: MapStyleSnapshot, forceAll: Bool) -> MapStyleDirtyDomains {
    guard !forceAll, let previous = lastSnapshot else {
      lastSnapshot = newSnapshot
      return .all
    }

    var dirty: MapStyleDirtyDomains = []

    if newSnapshot.chartSource != previous.chartSource {
      dirty.insert(.baseChart)
    }
    if newSnapshot.isOpenSeaMapOverlayEnabled != previous.isOpenSeaMapOverlayEnabled {
      dirty.insert(.openSeaMapOverlay)
    }
    // Persistent layers use data-driven expressions and in-place sprite replacement,
    // so theme switches (Glove Mode / Night palette) execute in O(1) without rebuilding GeoJSON shapes.
    if newSnapshot.marineTheme != previous.marineTheme {
      dirty.insert(.theme)
    }
    if newSnapshot.offlineMask != previous.offlineMask {
      dirty.insert(.offlineMask)
    }
    if newSnapshot.offlineHighlight != previous.offlineHighlight {
      dirty.insert(.offlineHighlight)
    }
    if newSnapshot.offlineSelectionBounds != previous.offlineSelectionBounds {
      dirty.insert(.offlineSelection)
    }
    if newSnapshot.gpsAccuracy != previous.gpsAccuracy {
      dirty.insert(.gpsAccuracy)
    }
    if newSnapshot.savedTrack != previous.savedTrack {
      dirty.insert(.savedTrack)
    }
    if newSnapshot.activeTrack != previous.activeTrack {
      dirty.insert(.activeTrack)
    }
    if newSnapshot.bearingLine != previous.bearingLine {
      dirty.insert(.bearingLine)
    }
    if newSnapshot.measureState != previous.measureState || newSnapshot.measureActivePin != previous.measureActivePin {
      dirty.insert(.measure)
    }
    if newSnapshot.visibleWaypoints != previous.visibleWaypoints {
      dirty.insert(.visibleWaypoints)
    }
    if newSnapshot.goToWaypoint != previous.goToWaypoint {
      dirty.insert(.goToWaypoint)
    }
    if newSnapshot.anchor != previous.anchor {
      dirty.insert(.anchor)
    }
    if newSnapshot.headingVector != previous.headingVector {
      dirty.insert(.headingVector)
    }
    if newSnapshot.vessel != previous.vessel {
      dirty.insert(.vessel)
    }
    if newSnapshot.isDataStale != previous.isDataStale {
      dirty.insert(.dataStale)
    }
    if newSnapshot.aimingCoordinate != previous.aimingCoordinate {
      dirty.insert(.aimingReticle)
    }

    lastSnapshot = newSnapshot
    return dirty
  }

  // MARK: - MapLibre Style Application

  /// Computes dirty domains and applies the required updates to `style` in deterministic Z-index order.
  /// `activeTrackPoints` is passed transiently and never stored so `TrackRecordingService.trackPoints` preserves O(1) CoW uniqueness.
  @discardableResult
  func apply(
    _ snapshot: MapStyleSnapshot,
    activeTrackPoints: ArraySlice<TrackPoint>,
    forceAll: Bool,
    to style: MLNStyle
  ) -> MapStyleDirtyDomains {
    let dirty = computeDirtyDomains(for: snapshot, forceAll: forceAll)
    guard !dirty.isEmpty else { return [] }

    // 1. Base Raster & Seamark Overlay
    // `RasterStyleRenderer.updateChartSource` already configures the OpenSeaMap overlay,
    // so skip a duplicate overlay call when a non-nil base chart source was just applied.
    var appliedOverlayViaBaseChart = false
    if dirty.contains(.baseChart), let chartSource = snapshot.chartSource {
      MapStyleController.updateChartSource(
        chartSource,
        in: style,
        isOverlayEnabled: snapshot.isOpenSeaMapOverlayEnabled
      )
      appliedOverlayViaBaseChart = true
    }
    if dirty.contains(.openSeaMapOverlay) && !appliedOverlayViaBaseChart {
      MapStyleController.updateOpenSeaMapOverlay(
        isEnabled: snapshot.isOpenSeaMapOverlayEnabled,
        in: style
      )
    }

    // 2. Persistent Vector Layer Hierarchy & Theme Styling
    if dirty.contains(.layerStructure) {
      MapStyleController.ensureAllLayers(in: style)
    }
    if dirty.contains(.theme) {
      MapStyleController.applyTheme(snapshot.marineTheme, in: style)
    }

    // 3. Offline Zones (Z-index 2..8)
    if dirty.contains(.offlineMask) {
      MapStyleController.updateOfflineMask(state: snapshot.offlineMask, in: style)
    }
    if dirty.contains(.offlineHighlight) {
      MapStyleController.updateOfflineHighlight(region: snapshot.offlineHighlight, in: style)
    }
    if dirty.contains(.offlineSelection) {
      MapStyleController.updateOfflineSelection(bounds: snapshot.offlineSelectionBounds, in: style)
    }

    // 4. Telemetry, Navigation, Chart Tools & Anchor Watch (Z-index 9..28)
    if dirty.contains(.gpsAccuracy) {
      MapStyleController.updateGpsAccuracy(state: snapshot.gpsAccuracy, in: style)
    }
    if dirty.contains(.savedTrack) {
      MapStyleController.updateSavedTrack(state: snapshot.savedTrack, in: style)
    }
    if dirty.contains(.activeTrack) {
      MapStyleController.updateActiveTrack(points: activeTrackPoints, in: style)
    }
    if dirty.contains(.bearingLine) {
      MapStyleController.updateBearingLine(state: snapshot.bearingLine, in: style)
    }
    if dirty.contains(.measure) {
      MapStyleController.updateMeasureLine(state: snapshot.measureState, in: style)
      MapStyleController.updateMeasurePins(
        state: snapshot.measureState,
        activePin: snapshot.measureActivePin,
        in: style
      )
    }
    if dirty.contains(.visibleWaypoints) {
      MapStyleController.updateVisibleWaypoints(states: snapshot.visibleWaypoints, in: style)
    }
    if dirty.contains(.goToWaypoint) {
      MapStyleController.updateGoToWaypoint(state: snapshot.goToWaypoint, in: style)
    }
    if dirty.contains(.anchor) {
      MapStyleController.updateAnchor(state: snapshot.anchor, in: style)
    }
    if dirty.contains(.headingVector) {
      MapStyleController.updateHeadingVector(data: snapshot.headingVector, in: style)
    }
    if dirty.contains(.vessel) {
      MapStyleController.updateVessel(state: snapshot.vessel, in: style)
    }
    if dirty.contains(.dataStale) {
      MapStyleController.updateDataStaleState(isStale: snapshot.isDataStale, in: style)
    }
    if dirty.contains(.aimingReticle) {
      MapStyleController.updateTargetAimingCrosshair(coordinate: snapshot.aimingCoordinate, in: style)
    }

    return dirty
  }

  // MARK: - High-Frequency Interactive Fast-Paths

  /// Directly updates the active offline selection rectangle during 60fps corner dragging
  /// while keeping `lastSnapshot` synchronized so background GPS renders never revert or double-render.
  func updateOfflineSelectionBounds(_ bounds: GeographicBoundingBox?, in style: MLNStyle?) {
    lastSnapshot?.offlineSelectionBounds = bounds
    if let style {
      MapStyleController.updateOfflineSelection(bounds: bounds, in: style)
    }
  }

  /// Directly updates the GPU aiming reticle during 120Hz long-press targeting while keeping `lastSnapshot` aligned.
  func updateAimingCoordinate(_ coordinate: CLLocationCoordinate2D?, in style: MLNStyle?) {
    lastSnapshot?.aimingCoordinate = coordinate
    if let style {
      MapStyleController.updateTargetAimingCrosshair(coordinate: coordinate, in: style)
    }
  }
}
