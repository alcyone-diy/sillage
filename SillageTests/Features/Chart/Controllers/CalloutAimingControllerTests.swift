//
//  CalloutAimingControllerTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreGraphics
import CoreLocation
import Foundation
import Testing
@testable import Sillage

@MainActor
@Suite("CalloutAimingController & WaypointMagneticSnap Candidate Tests")
struct CalloutAimingControllerTests {

  private static let laRochelle = CLLocationCoordinate2D(latitude: 46.1591, longitude: -1.1520)
  private static let ileDeRe = CLLocationCoordinate2D(latitude: 46.2031, longitude: -1.3670)

  private func makeSUT() -> (
    sut: CalloutAimingController,
    styleSynchronizer: MapStyleStateSynchronizer,
    cameraController: MapCameraController,
    calloutViewModel: MapCalloutViewModel
  ) {
    let sync = MapStyleStateSynchronizer()
    let camera = MapCameraController()
    let sut = CalloutAimingController(styleSynchronizer: sync, cameraController: camera)
    let calloutVM = MapCalloutViewModel()
    return (sut, sync, camera, calloutVM)
  }

  // MARK: - 6pt Long-Press Tremor Threshold

  @Test("Long-press drag threshold ignores < 6pt finger micro-tremors and latches once >= 6pt is reached")
  func longPressDragThresholdRejectsMicroTremorsThenLatches() {
    let (sut, _, _, _) = makeSUT()
    let start = CGPoint(x: 200, y: 300)
    sut.beginLongPressSession(at: start)

    #expect(sut.isLongPressActive == true)
    #expect(sut.hasDraggedDuringLongPress == false)

    // Sub-threshold finger micro-tremors (e.g. 3pt, 5.9pt) must be ignored to protect Glove Mode waypoint lock
    #expect(sut.acceptLongPressDragSample(at: CGPoint(x: 203, y: 304)) == false) // 5.0pt < 6.0pt
    #expect(sut.hasDraggedDuringLongPress == false)

    // Crossing >= 6pt latches `hasDraggedDuringLongPress`
    #expect(sut.acceptLongPressDragSample(at: CGPoint(x: 206, y: 300)) == true) // 6.0pt
    #expect(sut.hasDraggedDuringLongPress == true)

    // Once latched as an intentional drag, even fine positioning near the start point is accepted
    #expect(sut.acceptLongPressDragSample(at: CGPoint(x: 201, y: 300)) == true)
  }

  // MARK: - Re-entrancy Guard (`isStartingMagneticRecenter`) & Cancellation Cleanup

  @Test("performMagneticRecenter blocks synchronous re-entrant regionDidChange while allowing final arrival callback")
  func performMagneticRecenterSynchronousReentrancyGuard() {
    let (sut, _, _, calloutVM) = makeSUT()
    calloutVM.beginAiming(at: Self.laRochelle, waypointID: "wp-1", needsCentering: false)

    var canProcessDuringSynchronousCancellationCallback = true

    sut.performMagneticRecenter {
      // Simulate MapLibre's synchronous re-entrant `regionDidChangeWith` fired inside `setCenter(..., animated: true)`
      // when cancelling ongoing pan deceleration inertia:
      #expect(sut.isStartingMagneticRecenter == true)
      canProcessDuringSynchronousCancellationCallback = sut.shouldProcessRegionDidChange(
        calloutViewModel: calloutVM,
        isMeasureActive: false
      )
    }

    #expect(canProcessDuringSynchronousCancellationCallback == false)
    // Immediately after stack frame unwinds (`defer`), `isStartingMagneticRecenter` is cleared while `isMagneticRecentering` stays active
    #expect(sut.isStartingMagneticRecenter == false)
    #expect(sut.isMagneticRecentering == true)
    #expect(
      sut.shouldProcessRegionDidChange(calloutViewModel: calloutVM, isMeasureActive: false) == true
    )
  }

  @Test("cancelLongPressSession cleans up controller flags, aiming preview, and GPU aiming coordinate in synchronizer")
  func cancelLongPressSessionFullCleanup() {
    let (sut, sync, _, calloutVM) = makeSUT()

    // Seed synchronizer snapshot and active aiming preview
    let baseline = MapStyleSnapshot(
      chartSource: .openSeaMap,
      isOpenSeaMapOverlayEnabled: false,
      marineTheme: .standard,
      offlineMask: nil,
      offlineHighlight: nil,
      offlineSelectionBounds: nil,
      gpsAccuracy: nil,
      savedTrack: nil,
      activeTrack: ActiveTrackFingerprint(),
      bearingLine: nil,
      measureState: .inactive,
      measureActivePin: .end,
      visibleWaypoints: [],
      goToWaypoint: nil,
      anchor: nil,
      headingVector: nil,
      vessel: nil,
      isDataStale: false,
      aimingCoordinate: Self.ileDeRe
    )
    _ = sync.computeDirtyDomains(for: baseline, forceAll: false)

    sut.beginLongPressSession(at: CGPoint(x: 150, y: 250))
    _ = sut.acceptLongPressDragSample(at: CGPoint(x: 170, y: 250))
    calloutVM.startAimingPreview(at: Self.ileDeRe, waypointID: "wp-re")

    #expect(sut.isLongPressActive == true)
    #expect(sut.hasDraggedDuringLongPress == true)
    #expect(calloutVM.isCalloutVisible == true)
    #expect(sync.lastSnapshot?.aimingCoordinate == Self.ileDeRe)

    sut.cancelLongPressSession(calloutViewModel: calloutVM, style: nil)

    #expect(sut.isLongPressActive == false)
    #expect(sut.hasDraggedDuringLongPress == false)
    #expect(calloutVM.isCalloutVisible == false)
    #expect(calloutVM.aimingCoordinate == nil)
    #expect(sync.lastSnapshot?.aimingCoordinate == nil)
  }

  // MARK: - Zoom Retention & Candidate Filtering

  @Test("evaluateLockedWaypointRetention retains locked waypoint within detach radius and drops beyond")
  func lockedWaypointRetentionDuringZoom() {
    let reticle = CGPoint(x: 200, y: 320)

    let retained = CalloutAimingController.evaluateLockedWaypointRetention(
      reticlePoint: reticle,
      waypointScreenPoint: CGPoint(x: 215, y: 320), // 15pt <= 22pt detach radius
      waypointID: "wp-1",
      coordinate: Self.laRochelle,
      detachRadius: 22.0
    )
    #expect(retained?.waypointID == "wp-1")
    #expect(retained?.visualOffset == CGSize(width: 15, height: 0))

    let detached = CalloutAimingController.evaluateLockedWaypointRetention(
      reticlePoint: reticle,
      waypointScreenPoint: CGPoint(x: 225, y: 320), // 25pt > 22pt detach radius
      waypointID: "wp-1",
      coordinate: Self.laRochelle,
      detachRadius: 22.0
    )
    #expect(detached == nil)
  }

  @Test("WaypointMagneticSnap.makeCandidates excludes drafts, deduplicates GoTo, and supports antimeridian bounds")
  func candidateFilteringAndAntimeridianSupport() {
    let wpVisible = WaypointVisualState(
      id: "wp-east",
      name: "Fiji East",
      coordinate: CLLocationCoordinate2D(latitude: -17.8, longitude: 179.5),
      colorHex: "#00AAFF"
    )
    let wpDraft = WaypointVisualState(
      id: "wp-draft",
      name: "Draft",
      coordinate: CLLocationCoordinate2D(latitude: -17.8, longitude: -179.5),
      colorHex: "#FFAA00",
      isDraft: true
    )
    let wpGoToWest = WaypointVisualState(
      id: "wp-west",
      name: "Samoa West",
      coordinate: CLLocationCoordinate2D(latitude: -17.5, longitude: -179.4),
      colorHex: "#FF00FF"
    )

    // Viewport crossing the ±180° antimeridian (SW lon +179.0° > NE lon -179.0°)
    let candidates = WaypointMagneticSnap.makeCandidates(
      visibleWaypoints: [wpVisible, wpDraft, wpGoToWest],
      goToWaypoint: wpGoToWest, // duplicate of wpGoToWest in visibleWaypoints -> must be deduplicated
      draftWaypointID: nil,
      southWest: CLLocationCoordinate2D(latitude: -18.5, longitude: 179.0),
      northEast: CLLocationCoordinate2D(latitude: -17.0, longitude: -179.0),
      project: { coord in CGPoint(x: coord.longitude, y: coord.latitude) }
    )

    #expect(candidates.map(\.id) == ["wp-east", "wp-west"])
  }
}
