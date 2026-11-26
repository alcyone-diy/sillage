//
//  MapStyleStateSynchronizerTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreLocation
import Foundation
import Testing
@testable import Sillage

@MainActor
@Suite("MapStyleStateSynchronizer Tests")
struct MapStyleStateSynchronizerTests {

  // MARK: - Fixtures

  private static let laRochelle = CLLocationCoordinate2D(latitude: 46.1591, longitude: -1.1520)
  private static let ileDeRe = CLLocationCoordinate2D(latitude: 46.2031, longitude: -1.3670)
  private static let oleron = CLLocationCoordinate2D(latitude: 45.9325, longitude: -1.3090)

  private func makeBaselineSnapshot(
    chartSource: ChartSource? = .openSeaMap,
    isOpenSeaMapOverlayEnabled: Bool = false,
    marineTheme: MarineTheme = .standard,
    offlineMask: OfflineMaskVisualState? = nil,
    offlineHighlight: HighlightedOfflineRegion? = nil,
    offlineSelectionBounds: GeographicBoundingBox? = nil,
    gpsAccuracy: GpsAccuracyVisualState? = nil,
    savedTrack: SavedTrackVisualState? = nil,
    activeTrack: ActiveTrackFingerprint = ActiveTrackFingerprint(),
    bearingLine: BearingLineVisualState? = nil,
    measureState: MeasureState = .inactive,
    measureActivePin: ActiveMeasurePin = .end,
    visibleWaypoints: [WaypointVisualState] = [],
    goToWaypoint: WaypointVisualState? = nil,
    anchor: AnchorVisualState? = nil,
    headingVector: HeadingVectorData? = nil,
    vessel: VesselVisualState? = nil,
    isDataStale: Bool = false,
    aimingCoordinate: CLLocationCoordinate2D? = nil
  ) -> MapStyleSnapshot {
    MapStyleSnapshot(
      chartSource: chartSource,
      isOpenSeaMapOverlayEnabled: isOpenSeaMapOverlayEnabled,
      marineTheme: marineTheme,
      offlineMask: offlineMask,
      offlineHighlight: offlineHighlight,
      offlineSelectionBounds: offlineSelectionBounds,
      gpsAccuracy: gpsAccuracy,
      savedTrack: savedTrack,
      activeTrack: activeTrack,
      bearingLine: bearingLine,
      measureState: measureState,
      measureActivePin: measureActivePin,
      visibleWaypoints: visibleWaypoints,
      goToWaypoint: goToWaypoint,
      anchor: anchor,
      headingVector: headingVector,
      vessel: vessel,
      isDataStale: isDataStale,
      aimingCoordinate: aimingCoordinate
    )
  }

  private func makeTrackPoint(timestamp: Date, coordinate: CLLocationCoordinate2D = Self.laRochelle) -> TrackPoint {
    TrackPoint(
      timestamp: timestamp,
      segmentIndex: 0,
      coordinate: coordinate,
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters)
    )
  }

  // MARK: - Initial Sync & Force Reload

  @Test("Initial sync with nil lastSnapshot marks all domains dirty")
  func initialSyncReturnsAllDomains() {
    let sut = MapStyleStateSynchronizer()
    let snapshot = makeBaselineSnapshot()

    #expect(sut.lastSnapshot == nil)
    let dirty = sut.computeDirtyDomains(for: snapshot, forceAll: false)

    #expect(dirty == .all)
    #expect(sut.lastSnapshot == snapshot)
  }

  @Test("Consecutive identical snapshot returns empty dirty set")
  func consecutiveIdenticalSnapshotReturnsEmpty() {
    let sut = MapStyleStateSynchronizer()
    let snapshot = makeBaselineSnapshot()

    _ = sut.computeDirtyDomains(for: snapshot, forceAll: false)
    let secondDirty = sut.computeDirtyDomains(for: snapshot, forceAll: false)

    #expect(secondDirty.isEmpty)
  }

  @Test("forceAll returns all domains even on an identical snapshot, preserving active GPU aiming reticle")
  func forceAllOnIdenticalSnapshotReturnsAllAndPreservesAimingReticle() {
    let sut = MapStyleStateSynchronizer()
    let snapshot = makeBaselineSnapshot(aimingCoordinate: Self.ileDeRe)

    _ = sut.computeDirtyDomains(for: snapshot, forceAll: false)
    #expect(sut.computeDirtyDomains(for: snapshot, forceAll: false).isEmpty)

    let reloadDirty = sut.computeDirtyDomains(for: snapshot, forceAll: true)
    #expect(reloadDirty == .all)
    #expect(reloadDirty.contains(.layerStructure))
    #expect(reloadDirty.contains(.aimingReticle))
    #expect(sut.lastSnapshot?.aimingCoordinate == Self.ileDeRe)
  }

  // MARK: - Isolated Single-Domain Mutations

  @Test("Mutating chartSource or OpenSeaMap overlay independently marks only its own domain")
  func baseChartAndOverlayDiffIndependently() {
    let sut = MapStyleStateSynchronizer()
    _ = sut.computeDirtyDomains(for: makeBaselineSnapshot(), forceAll: false)

    let sourceChanged = sut.computeDirtyDomains(
      for: makeBaselineSnapshot(chartSource: .remoteGeoGarage(clientID: "cid", layerID: "shom")),
      forceAll: false
    )
    #expect(sourceChanged == [.baseChart])

    let overlayToggled = sut.computeDirtyDomains(
      for: makeBaselineSnapshot(
        chartSource: .remoteGeoGarage(clientID: "cid", layerID: "shom"),
        isOpenSeaMapOverlayEnabled: true
      ),
      forceAll: false
    )
    #expect(overlayToggled == [.openSeaMapOverlay])
  }

  @Test("Switching MarineTheme marks strictly .theme in O(1) without invalidating GeoJSON domains")
  func marineThemeChangeMarksOnlyThemeDomain() {
    let sut = MapStyleStateSynchronizer()
    _ = sut.computeDirtyDomains(for: makeBaselineSnapshot(marineTheme: .standard), forceAll: false)

    let dirty = sut.computeDirtyDomains(for: makeBaselineSnapshot(marineTheme: .gloveMode), forceAll: false)
    #expect(dirty == [.theme])
  }

  @Test("Each visual domain triggers strictly its corresponding dirty flag")
  func individualVisualDomainMutations() {
    let sut = MapStyleStateSynchronizer()
    var current = makeBaselineSnapshot()
    _ = sut.computeDirtyDomains(for: current, forceAll: false)

    // Offline mask
    let mask = OfflineMaskVisualState(isActive: true)
    current = makeBaselineSnapshot(offlineMask: mask)
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.offlineMask])

    // Offline highlight
    let bounds = GeographicBoundingBox(southWest: Self.laRochelle, northEast: Self.ileDeRe)
    let highlight = HighlightedOfflineRegion(id: UUID(), name: "Pertuis", bounds: bounds, layerID: "shom")
    current = makeBaselineSnapshot(offlineMask: mask, offlineHighlight: highlight)
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.offlineHighlight])

    // Offline selection
    current = makeBaselineSnapshot(offlineMask: mask, offlineHighlight: highlight, offlineSelectionBounds: bounds)
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.offlineSelection])

    // GPS Accuracy
    let accuracy = GpsAccuracyVisualState(coordinates: [Self.laRochelle, Self.ileDeRe, Self.oleron])
    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.gpsAccuracy])

    // Saved track
    let savedTrack = SavedTrackVisualState(segments: [[Self.laRochelle, Self.ileDeRe]])
    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy,
      savedTrack: savedTrack
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.savedTrack])

    // Bearing line
    let bearing = BearingLineVisualState(coordinates: [Self.laRochelle, Self.ileDeRe], colorHex: "#FF00FF")
    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy,
      savedTrack: savedTrack,
      bearingLine: bearing
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.bearingLine])

    // Measure state & active pin
    let measureActive: MeasureState = .active(start: Self.laRochelle, end: Self.ileDeRe)
    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy,
      savedTrack: savedTrack,
      bearingLine: bearing,
      measureState: measureActive,
      measureActivePin: .end
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.measure])

    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy,
      savedTrack: savedTrack,
      bearingLine: bearing,
      measureState: measureActive,
      measureActivePin: .start
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.measure])

    // Waypoints & GoTo
    let wp = WaypointVisualState(id: "wp-1", name: "Chauveau", coordinate: Self.ileDeRe, colorHex: "#00AAFF")
    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy,
      savedTrack: savedTrack,
      bearingLine: bearing,
      measureState: measureActive,
      measureActivePin: .start,
      visibleWaypoints: [wp]
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.visibleWaypoints])

    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy,
      savedTrack: savedTrack,
      bearingLine: bearing,
      measureState: measureActive,
      measureActivePin: .start,
      visibleWaypoints: [wp],
      goToWaypoint: wp
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.goToWaypoint])

    // Anchor
    let anchor = AnchorVisualState(
      status: .armed,
      pointCoordinate: Self.laRochelle,
      radius: Measurement(value: 40.0, unit: .meters),
      vesselCoordinate: Self.ileDeRe
    )
    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy,
      savedTrack: savedTrack,
      bearingLine: bearing,
      measureState: measureActive,
      measureActivePin: .start,
      visibleWaypoints: [wp],
      goToWaypoint: wp,
      anchor: anchor
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.anchor])

    // Heading vector
    let heading = HeadingVectorData(
      lineCoordinates: [Self.laRochelle, Self.ileDeRe],
      majorTickCoordinates: [Self.ileDeRe],
      minorTickCoordinates: []
    )
    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy,
      savedTrack: savedTrack,
      bearingLine: bearing,
      measureState: measureActive,
      measureActivePin: .start,
      visibleWaypoints: [wp],
      goToWaypoint: wp,
      anchor: anchor,
      headingVector: heading
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.headingVector])

    // Vessel
    let vessel = VesselVisualState(
      coordinate: Self.laRochelle,
      course: Measurement(value: 270.0, unit: .degrees),
      isStale: false,
      isDegraded: false
    )
    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy,
      savedTrack: savedTrack,
      bearingLine: bearing,
      measureState: measureActive,
      measureActivePin: .start,
      visibleWaypoints: [wp],
      goToWaypoint: wp,
      anchor: anchor,
      headingVector: heading,
      vessel: vessel
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.vessel])

    // Data stale
    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy,
      savedTrack: savedTrack,
      bearingLine: bearing,
      measureState: measureActive,
      measureActivePin: .start,
      visibleWaypoints: [wp],
      goToWaypoint: wp,
      anchor: anchor,
      headingVector: heading,
      vessel: vessel,
      isDataStale: true
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.dataStale])

    // Aiming reticle
    current = makeBaselineSnapshot(
      offlineMask: mask,
      offlineHighlight: highlight,
      offlineSelectionBounds: bounds,
      gpsAccuracy: accuracy,
      savedTrack: savedTrack,
      bearingLine: bearing,
      measureState: measureActive,
      measureActivePin: .start,
      visibleWaypoints: [wp],
      goToWaypoint: wp,
      anchor: anchor,
      headingVector: heading,
      vessel: vessel,
      isDataStale: true,
      aimingCoordinate: Self.oleron
    )
    #expect(sut.computeDirtyDomains(for: current, forceAll: false) == [.aimingReticle])
  }

  // MARK: - ActiveTrackFingerprint O(1) & CoW Uniqueness

  @Test("ActiveTrackFingerprint detects appends, clears, and ring-buffer head truncations without retaining slice buffer")
  func activeTrackFingerprintDetectsChangesAndPreservesBufferUniqueness() {
    let sut = MapStyleStateSynchronizer()
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 1_001)
    let t2 = Date(timeIntervalSince1970: 1_002)

    let p0 = makeTrackPoint(timestamp: t0)
    let p1 = makeTrackPoint(timestamp: t1)
    let p2 = makeTrackPoint(timestamp: t2)

    var liveBuffer: ArraySlice<TrackPoint> = [p0, p1]
    liveBuffer.reserveCapacity(16)
    let initialBufferAddress = liveBuffer.withUnsafeBufferPointer { $0.baseAddress }

    let twoPoints = ActiveTrackFingerprint(points: liveBuffer)
    _ = sut.computeDirtyDomains(for: makeBaselineSnapshot(activeTrack: twoPoints), forceAll: false)

    // Verify `lastSnapshot` does NOT retain `liveBuffer` storage: appending mutates in-place at the exact same address!
    liveBuffer.append(p2)
    let postAppendBufferAddress = liveBuffer.withUnsafeBufferPointer { $0.baseAddress }
    #expect(initialBufferAddress == postAppendBufferAddress)

    // Same fingerprint -> clean
    #expect(sut.computeDirtyDomains(for: makeBaselineSnapshot(activeTrack: twoPoints), forceAll: false).isEmpty)

    // Appended buffer -> detected
    #expect(
      sut.computeDirtyDomains(
        for: makeBaselineSnapshot(activeTrack: ActiveTrackFingerprint(points: liveBuffer)),
        forceAll: false
      ) == [.activeTrack]
    )

    // Head truncation with same count & same last timestamp (e.g. [p1, p1, p2] vs [p0, p1, p2]) -> detected via firstTimestamp!
    let headTruncatedSameCount = ActiveTrackFingerprint(points: ArraySlice([p1, p1, p2]))
    #expect(sut.computeDirtyDomains(for: makeBaselineSnapshot(activeTrack: headTruncatedSameCount), forceAll: false) == [.activeTrack])

    // Clear -> detected
    #expect(sut.computeDirtyDomains(for: makeBaselineSnapshot(activeTrack: ActiveTrackFingerprint()), forceAll: false) == [.activeTrack])
  }

  // MARK: - Direct Gesture Fast-Paths

  @Test("Gesture fast-paths keep lastSnapshot aligned so subsequent identical snapshots return empty")
  func gestureFastPathsKeepLastSnapshotAligned() {
    let sut = MapStyleStateSynchronizer()

    // Calling fast-path before initial sync must not create a partial snapshot
    sut.updateAimingCoordinate(Self.laRochelle, in: nil)
    #expect(sut.lastSnapshot == nil)

    // Initial sync
    _ = sut.computeDirtyDomains(for: makeBaselineSnapshot(), forceAll: false)

    // 1. Offline selection corner drag fast-path
    let draggedBounds = GeographicBoundingBox(southWest: Self.oleron, northEast: Self.ileDeRe)
    sut.updateOfflineSelectionBounds(draggedBounds, in: nil)
    #expect(sut.lastSnapshot?.offlineSelectionBounds == draggedBounds)
    #expect(
      sut.computeDirtyDomains(
        for: makeBaselineSnapshot(offlineSelectionBounds: draggedBounds),
        forceAll: false
      ).isEmpty
    )

    // 2. 120Hz GPU aiming reticle fast-path
    sut.updateAimingCoordinate(Self.ileDeRe, in: nil)
    #expect(
      sut.computeDirtyDomains(
        for: makeBaselineSnapshot(
          offlineSelectionBounds: draggedBounds,
          aimingCoordinate: Self.ileDeRe
        ),
        forceAll: false
      ).isEmpty
    )
  }
}
