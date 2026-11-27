//
//  CalloutAimingController.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreGraphics
import CoreLocation
import Foundation
import MapLibre
import QuartzCore
import SwiftUI
import UIKit

/// Owns the marine contextual callout aiming reticle state machine:
/// long-press inspection, 6pt Glove Mode tremor tolerance, 120Hz waypoint magnetic pull,
/// pan deceleration inertia capture, and zero-flicker GPU-to-SwiftUI crosshair handoff.
/// Never mutates `MLNMapView` directly — delegates all camera positioning synchronously to `MapCameraController`.
@MainActor
final class CalloutAimingController {

  private let styleSynchronizer: MapStyleStateSynchronizer
  private let cameraController: MapCameraController

  private(set) var isLongPressActive: Bool = false
  private(set) var hasDraggedDuringLongPress: Bool = false
  private var longPressBeganPoint: CGPoint?

  private(set) var isMagneticRecentering: Bool = false
  private(set) var isStartingMagneticRecenter: Bool = false
  private(set) var isUserPanMoveActive: Bool = false
  private(set) var isZoomMoveActive: Bool = false
  private(set) var panStartWaypointID: String?

  private let snapFeedbackGenerator = UISelectionFeedbackGenerator()
  private var lastLongPressUpdateTime: CFTimeInterval = 0
  private var lastTargetUpdateTime: CFTimeInterval = 0

  nonisolated static let longPressDragThreshold: CGFloat = 6.0
  private static let longPressThrottleInterval: CFTimeInterval = 0.016
  private static let emptyWaterTargetThrottleInterval: CFTimeInterval = 0.032

  init(
    styleSynchronizer: MapStyleStateSynchronizer,
    cameraController: MapCameraController
  ) {
    self.styleSynchronizer = styleSynchronizer
    self.cameraController = cameraController
  }

  var isInteracting: Bool {
    isLongPressActive
  }

  // MARK: - Pure Testable Geometry & State Invariants (No MLNMapView Dependency)

  /// Nominal screen position of the aiming crosshair (40% from top), or `nil` when viewport bounds are empty.
  nonisolated static func reticleScreenPoint(
    in bounds: CGRect,
    yFraction: CGFloat = AppConstants.Map.aimingCrosshairYFraction
  ) -> CGPoint? {
    guard bounds.width > 0, bounds.height > 0 else {
      return nil
    }
    return CGPoint(
      x: bounds.midX,
      y: bounds.height * yFraction
    )
  }

  /// Returns `true` once finger displacement exceeds the 6pt sub-threshold tremor guard,
  /// preventing Glove Mode waypoint locks (30–33pt) from detaching prematurely on stationary holds.
  nonisolated static func hasExceededLongPressDragThreshold(
    from beganPoint: CGPoint,
    to currentPoint: CGPoint,
    threshold: CGFloat = longPressDragThreshold
  ) -> Bool {
    hypot(currentPoint.x - beganPoint.x, currentPoint.y - beganPoint.y) >= threshold
  }

  /// Evaluates whether an already-locked waypoint remains within its detach radius during a zoom gesture
  /// without ever acquiring a new neighboring waypoint.
  nonisolated static func evaluateLockedWaypointRetention(
    reticlePoint: CGPoint,
    waypointScreenPoint: CGPoint,
    waypointID: String,
    coordinate: CLLocationCoordinate2D,
    detachRadius: CGFloat
  ) -> WaypointSnapResult? {
    let offset = CGSize(
      width: waypointScreenPoint.x - reticlePoint.x,
      height: waypointScreenPoint.y - reticlePoint.y
    )
    guard hypot(offset.width, offset.height) <= detachRadius else { return nil }
    return WaypointSnapResult(waypointID: waypointID, coordinate: coordinate, visualOffset: offset)
  }

  /// Begins a long-press session at `touchPoint` (testable state entry point).
  func beginLongPressSession(at touchPoint: CGPoint, now: CFTimeInterval = CACurrentMediaTime()) {
    isLongPressActive = true
    hasDraggedDuringLongPress = false
    longPressBeganPoint = touchPoint
    isMagneticRecentering = false
    lastLongPressUpdateTime = now
  }

  /// Evaluates whether a `.changed` long-press sample should be ignored due to sub-threshold finger tremor.
  func acceptLongPressDragSample(at touchPoint: CGPoint) -> Bool {
    if !hasDraggedDuringLongPress {
      if let beganPoint = longPressBeganPoint,
         !Self.hasExceededLongPressDragThreshold(from: beganPoint, to: touchPoint) {
        return false
      }
      hasDraggedDuringLongPress = true
    }
    return true
  }

  /// Resets all long-press state and clears any active aiming preview on `.cancelled` / `.failed`.
  func cancelLongPressSession(calloutViewModel: MapCalloutViewModel, style: MLNStyle?) {
    isLongPressActive = false
    hasDraggedDuringLongPress = false
    longPressBeganPoint = nil
    if calloutViewModel.aimingCoordinate != nil {
      styleSynchronizer.updateAimingCoordinate(nil, in: style)
      calloutViewModel.cancelAimingPreview()
    }
  }

  /// Returns whether `regionDidChangeWith` should process reticle handoff / magnetic settle.
  /// Guarded by `!isStartingMagneticRecenter` so MapLibre's synchronous re-entrant inertia-cancellation
  /// callback during `performMagneticRecenter` is ignored while the subsequent arrival callback proceeds.
  func shouldProcessRegionDidChange(
    calloutViewModel: MapCalloutViewModel,
    isMeasureActive: Bool
  ) -> Bool {
    !isStartingMagneticRecenter &&
    !isLongPressActive &&
    calloutViewModel.isCalloutVisible &&
    !isMeasureActive
  }

  /// Executes a synchronous camera recenter onto a magnetically captured waypoint while holding the
  /// `isStartingMagneticRecenter` re-entrancy guard across the stack frame.
  func performMagneticRecenter(_ synchronousCenterAction: () -> Void) {
    isMagneticRecentering = true
    isUserPanMoveActive = false
    panStartWaypointID = nil
    isStartingMagneticRecenter = true
    defer { isStartingMagneticRecenter = false }
    synchronousCenterAction()
  }

  // MARK: - Viewport Resize Handling

  func handleViewportResize(
    in mapView: MLNMapView,
    calloutViewModel: MapCalloutViewModel
  ) {
    guard calloutViewModel.isCentering,
          let target = calloutViewModel.targetCoordinate,
          let style = mapView.style,
          let targetScreenPoint = Self.reticleScreenPoint(in: mapView.bounds) else {
      return
    }
    cameraController.centerCoordinate(
      target,
      atScreenPoint: targetScreenPoint,
      in: mapView,
      resetContentInset: false,
      animated: false
    )
    let targetWaypointID = calloutViewModel.targetWaypointID
    let resolvedCoord = targetWaypointID != nil
      ? target
      : mapView.convert(targetScreenPoint, toCoordinateFrom: mapView)
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      calloutViewModel.interruptCentering(at: resolvedCoord, waypointID: targetWaypointID)
    }
    styleSynchronizer.updateAimingCoordinate(nil, in: style)
  }

  // MARK: - Long-Press Gesture Handling

  func handleLongPress(
    _ sender: UILongPressGestureRecognizer,
    in mapView: MLNMapView,
    viewModel: ChartViewModel,
    theme: MarineTheme,
    snapCandidatesProvider: (MLNMapView) -> [WaypointSnapCandidate]
  ) {
    if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {
      isLongPressActive = false
    }

    let calloutVM = viewModel.calloutViewModel
    let touchPoint = sender.location(in: mapView)

    switch sender.state {
    case .began:
      beginLongPressSession(at: touchPoint)
      snapFeedbackGenerator.prepare()
      viewModel.chartInteractedByUser()

      let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
      feedbackGenerator.impactOccurred()

      // Respect Glove Mode touch target sizing (44pt standard, 66pt glove mode) for initial waypoint hit-testing
      let hitSize = theme.minTouchTarget
      let halfHitSize = hitSize / 2.0
      let touchRect = CGRect(
        x: touchPoint.x - halfHitSize,
        y: touchPoint.y - halfHitSize,
        width: hitSize,
        height: hitSize
      )
      let features = mapView.visibleFeatures(
        in: touchRect,
        styleLayerIdentifiers: [
          MapLayerIdentifier.goToWaypoint.rawValue,
          MapLayerIdentifier.visibleWaypoints.rawValue
        ]
      )

      let draftID = viewModel.draftWaypointID
      var containsDraftFeature = false
      var closestWaypoint: (feature: MLNPointFeature, id: String, distance: CGFloat)? = nil

      for case let feature as MLNPointFeature in features {
        guard let id = feature.attributes[MapFeatureKey.id.rawValue] as? String else { continue }
        if id == draftID {
          containsDraftFeature = true
          continue
        }
        let pt = mapView.convert(feature.coordinate, toPointTo: mapView)
        let dist = hypot(pt.x - touchPoint.x, pt.y - touchPoint.y)
        if let existing = closestWaypoint {
          if dist < existing.distance {
            closestWaypoint = (feature, id, dist)
          }
        } else {
          closestWaypoint = (feature, id, dist)
        }
      }

      if let hit = closestWaypoint {
        styleSynchronizer.updateAimingCoordinate(hit.feature.coordinate, in: mapView.style)
        calloutVM.startAimingPreview(at: hit.feature.coordinate, waypointID: hit.id)
      } else if containsDraftFeature {
        // Interacting exclusively with the draft waypoint currently being created: ignore map callout presentation
        break
      } else {
        let targetCoordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
        styleSynchronizer.updateAimingCoordinate(targetCoordinate, in: mapView.style)
        calloutVM.startAimingPreview(at: targetCoordinate, waypointID: nil)
      }

    case .changed:
      guard calloutVM.aimingCoordinate != nil else { break }
      let now = CACurrentMediaTime()
      guard now - lastLongPressUpdateTime >= Self.longPressThrottleInterval else { break }
      lastLongPressUpdateTime = now

      let currentTouchPoint = sender.location(in: mapView)
      guard acceptLongPressDragSample(at: currentTouchPoint) else { break }

      let previousWaypointID = calloutVM.targetWaypointID
      let snap = evaluateSnap(
        at: currentTouchPoint,
        in: mapView,
        theme: theme,
        currentlySnappedID: previousWaypointID,
        snapCandidatesProvider: snapCandidatesProvider
      )

      let updatedCoordinate: CLLocationCoordinate2D
      let updatedWaypointID: String?
      if let snap {
        updatedCoordinate = snap.coordinate
        updatedWaypointID = snap.waypointID
        if snap.waypointID != previousWaypointID {
          snapFeedbackGenerator.selectionChanged()
        }
      } else {
        updatedCoordinate = mapView.convert(currentTouchPoint, toCoordinateFrom: mapView)
        updatedWaypointID = nil
      }

      styleSynchronizer.updateAimingCoordinate(updatedCoordinate, in: mapView.style)
      calloutVM.updateAimingPreview(at: updatedCoordinate, waypointID: updatedWaypointID)

    case .ended:
      isLongPressActive = false
      longPressBeganPoint = nil
      if let currentAimingCoordinate = calloutVM.aimingCoordinate {
        let resolvedCoordinate: CLLocationCoordinate2D
        let resolvedWaypointID: String?

        // Preserve initial Glove Mode touch-target lock if the user released without dragging,
        // since minTouchTarget/2 (33pt) intentionally exceeds the magnetic detach radius (30pt).
        if !hasDraggedDuringLongPress, let lockedID = calloutVM.targetWaypointID {
          resolvedCoordinate = currentAimingCoordinate
          resolvedWaypointID = lockedID
        } else if let snap = evaluateSnap(
          at: touchPoint,
          in: mapView,
          theme: theme,
          currentlySnappedID: calloutVM.targetWaypointID,
          snapCandidatesProvider: snapCandidatesProvider
        ) {
          resolvedCoordinate = snap.coordinate
          resolvedWaypointID = snap.waypointID
        } else {
          resolvedCoordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
          resolvedWaypointID = nil
        }

        styleSynchronizer.updateAimingCoordinate(resolvedCoordinate, in: mapView.style)

        let targetScreenPoint = CGPoint(
          x: mapView.bounds.midX,
          y: mapView.bounds.height * AppConstants.Map.aimingCrosshairYFraction
        )
        let resolvedScreenPoint = mapView.convert(resolvedCoordinate, toPointTo: mapView)
        let isNearCenter = hypot(
          resolvedScreenPoint.x - targetScreenPoint.x,
          resolvedScreenPoint.y - targetScreenPoint.y
        ) < 1.0

        if !isNearCenter {
          calloutVM.beginAiming(
            at: resolvedCoordinate,
            waypointID: resolvedWaypointID,
            needsCentering: true
          )
          cameraController.centerCoordinate(
            resolvedCoordinate,
            atScreenPoint: targetScreenPoint,
            in: mapView,
            resetContentInset: viewModel.trackingMode != .courseUp,
            animated: true
          )
        } else {
          var transaction = Transaction()
          transaction.disablesAnimations = true
          withTransaction(transaction) {
            calloutVM.beginAiming(
              at: resolvedCoordinate,
              waypointID: resolvedWaypointID,
              needsCentering: false
            )
          }
        }
      }

    case .cancelled, .failed:
      cancelLongPressSession(calloutViewModel: calloutVM, style: mapView.style)

    default:
      break
    }
  }

  // MARK: - Map Region Change Hooks (120Hz Reticle & Zero-Flicker Handoff)

  func regionWillChange(
    in mapView: MLNMapView,
    reason: MLNCameraChangeReason,
    viewModel: ChartViewModel,
    theme: MarineTheme,
    snapCandidatesProvider: (MLNMapView) -> [WaypointSnapCandidate]
  ) {
    if !reason.contains(.programmatic) {
      isMagneticRecentering = false
      let isZoom = MapCameraController.isZoomReason(reason)
      let isUserPan = reason.contains(.gesturePan) && !isZoom
      isZoomMoveActive = isZoom
      isUserPanMoveActive = isUserPan
      panStartWaypointID = isUserPan ? viewModel.calloutViewModel.targetWaypointID : nil
      snapFeedbackGenerator.prepare()

      let calloutVM = viewModel.calloutViewModel
      if calloutVM.isCalloutVisible &&
         !viewModel.measureToolViewModel.isActive &&
         calloutVM.isCentering,
         let reticlePoint = Self.reticleScreenPoint(in: mapView.bounds) {
        let snap = evaluateSnap(
          at: reticlePoint,
          in: mapView,
          theme: theme,
          currentlySnappedID: calloutVM.targetWaypointID,
          snapCandidatesProvider: snapCandidatesProvider
        )
        let resolvedCoord = snap?.coordinate ?? mapView.convert(reticlePoint, toCoordinateFrom: mapView)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          calloutVM.interruptCentering(
            at: resolvedCoord,
            waypointID: snap?.waypointID,
            visualOffset: snap?.visualOffset ?? .zero
          )
        }
      }
    } else {
      isZoomMoveActive = false
      isUserPanMoveActive = false
      panStartWaypointID = nil
    }
  }

  func regionIsChanging(
    in mapView: MLNMapView,
    viewModel: ChartViewModel,
    theme: MarineTheme,
    excludedGestureRecognizer: UIGestureRecognizer?,
    snapCandidatesProvider: (MLNMapView) -> [WaypointSnapCandidate]
  ) {
    let calloutVM = viewModel.calloutViewModel
    guard calloutVM.isCalloutVisible,
          !viewModel.measureToolViewModel.isActive,
          !calloutVM.isCentering,
          calloutVM.aimingCoordinate == nil,
          let reticlePoint = Self.reticleScreenPoint(in: mapView.bounds) else {
      return
    }

    if isMagneticRecentering,
       calloutVM.targetWaypointID != nil,
       let lockedCoord = calloutVM.targetCoordinate {
      let lockedPoint = mapView.convert(lockedCoord, toPointTo: mapView)
      let shrinkingOffset = CGSize(
        width: lockedPoint.x - reticlePoint.x,
        height: lockedPoint.y - reticlePoint.y
      )
      calloutVM.updateReticleVisualOffset(shrinkingOffset)
    } else if isZoomMoveActive {
      let now = CACurrentMediaTime()
      if let lockedID = calloutVM.targetWaypointID, let lockedCoord = calloutVM.targetCoordinate {
        let wpPoint = mapView.convert(lockedCoord, toPointTo: mapView)
        if let retained = Self.evaluateLockedWaypointRetention(
          reticlePoint: reticlePoint,
          waypointScreenPoint: wpPoint,
          waypointID: lockedID,
          coordinate: lockedCoord,
          detachRadius: magneticDetachRadius(for: theme)
        ) {
          calloutVM.updateReticleVisualOffset(retained.visualOffset)
        } else {
          lastTargetUpdateTime = now
          let targetCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
          calloutVM.updateTarget(coordinate: targetCoord, waypointID: nil, visualOffset: .zero)
        }
      } else if now - lastTargetUpdateTime >= Self.emptyWaterTargetThrottleInterval {
        lastTargetUpdateTime = now
        let targetCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
        calloutVM.updateTarget(coordinate: targetCoord, waypointID: nil, visualOffset: .zero)
      }
    } else {
      let previousWaypointID = calloutVM.targetWaypointID
      let snap = evaluateSnap(
        at: reticlePoint,
        in: mapView,
        theme: theme,
        currentlySnappedID: previousWaypointID,
        snapCandidatesProvider: snapCandidatesProvider
      )

      let now = CACurrentMediaTime()
      if let snap {
        if snap.waypointID != previousWaypointID {
          snapFeedbackGenerator.selectionChanged()
          lastTargetUpdateTime = now
          calloutVM.updateTarget(
            coordinate: snap.coordinate,
            waypointID: snap.waypointID,
            visualOffset: snap.visualOffset
          )
        } else {
          calloutVM.updateReticleVisualOffset(snap.visualOffset)
        }

        // Stop pan deceleration inertia once the finger is off screen so the reticle catches
        // a waypoint instead of coasting past it, while never blocking an active finger drag
        // or a short flick meant to leave the waypoint already targeted when the pan began.
        if isUserPanMoveActive &&
           !hasActiveMapTouchGesture(in: mapView, excluding: excludedGestureRecognizer) &&
           snap.waypointID != panStartWaypointID {
          let offsetDistance = hypot(snap.visualOffset.width, snap.visualOffset.height)
          if offsetDistance > 1.0 {
            performMagneticRecenter {
              cameraController.centerCoordinate(
                snap.coordinate,
                atScreenPoint: reticlePoint,
                in: mapView,
                resetContentInset: false,
                animated: true
              )
            }
          }
        }
      } else if previousWaypointID != nil {
        panStartWaypointID = nil
        lastTargetUpdateTime = now
        let targetCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
        calloutVM.updateTarget(coordinate: targetCoord, waypointID: nil, visualOffset: .zero)
      } else if now - lastTargetUpdateTime >= Self.emptyWaterTargetThrottleInterval {
        lastTargetUpdateTime = now
        let targetCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
        calloutVM.updateTarget(coordinate: targetCoord, waypointID: nil, visualOffset: .zero)
      }
    }
  }

  func regionDidChange(
    in mapView: MLNMapView,
    reason: MLNCameraChangeReason,
    viewModel: ChartViewModel,
    theme: MarineTheme,
    snapCandidatesProvider: (MLNMapView) -> [WaypointSnapCandidate]
  ) {
    let wasZoomMove = isZoomMoveActive || MapCameraController.isZoomReason(reason)
    isZoomMoveActive = false
    isUserPanMoveActive = false
    panStartWaypointID = nil

    let calloutVM = viewModel.calloutViewModel
    guard shouldProcessRegionDidChange(
      calloutViewModel: calloutVM,
      isMeasureActive: viewModel.measureToolViewModel.isActive
    ),
    let reticlePoint = Self.reticleScreenPoint(in: mapView.bounds) else {
      return
    }

    if calloutVM.isCentering {
      let resolvedCoord: CLLocationCoordinate2D
      let resolvedWaypointID: String?
      if let lockedID = calloutVM.targetWaypointID, let lockedCoord = calloutVM.targetCoordinate {
        resolvedCoord = lockedCoord
        resolvedWaypointID = lockedID
      } else if let snap = evaluateSnap(
        at: reticlePoint,
        in: mapView,
        theme: theme,
        currentlySnappedID: calloutVM.targetWaypointID,
        snapCandidatesProvider: snapCandidatesProvider
      ) {
        resolvedCoord = snap.coordinate
        resolvedWaypointID = snap.waypointID
      } else {
        resolvedCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
        resolvedWaypointID = nil
      }

      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        calloutVM.completeCentering(at: resolvedCoord, waypointID: resolvedWaypointID)
      }
    } else {
      let snap: WaypointSnapResult?
      if wasZoomMove {
        if let lockedID = calloutVM.targetWaypointID, let lockedCoord = calloutVM.targetCoordinate {
          let wpPoint = mapView.convert(lockedCoord, toPointTo: mapView)
          snap = Self.evaluateLockedWaypointRetention(
            reticlePoint: reticlePoint,
            waypointScreenPoint: wpPoint,
            waypointID: lockedID,
            coordinate: lockedCoord,
            detachRadius: magneticDetachRadius(for: theme)
          )
        } else {
          snap = nil
        }
      } else {
        snap = evaluateSnap(
          at: reticlePoint,
          in: mapView,
          theme: theme,
          currentlySnappedID: calloutVM.targetWaypointID,
          snapCandidatesProvider: snapCandidatesProvider
        )
      }

      if let snap {
        let offsetDistance = hypot(snap.visualOffset.width, snap.visualOffset.height)
        if offsetDistance > 1.0 && !isMagneticRecentering {
          isMagneticRecentering = true
          calloutVM.updateTarget(
            coordinate: snap.coordinate,
            waypointID: snap.waypointID,
            visualOffset: snap.visualOffset
          )
          cameraController.centerCoordinate(
            snap.coordinate,
            atScreenPoint: reticlePoint,
            in: mapView,
            resetContentInset: false,
            animated: true
          )
        } else {
          isMagneticRecentering = false
          calloutVM.updateTarget(
            coordinate: snap.coordinate,
            waypointID: snap.waypointID,
            visualOffset: .zero
          )
        }
      } else {
        isMagneticRecentering = false
        let aimingCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
        calloutVM.updateTarget(coordinate: aimingCoord, waypointID: nil, visualOffset: .zero)
      }
    }
  }

  // MARK: - Private Helpers

  private func magneticAttachRadius(for theme: MarineTheme) -> CGFloat {
    theme.isGloveMode
      ? AppConstants.Map.waypointMagneticSnapGloveRadius
      : AppConstants.Map.waypointMagneticSnapRadius
  }

  private func magneticDetachRadius(for theme: MarineTheme) -> CGFloat {
    magneticAttachRadius(for: theme) + AppConstants.Map.waypointMagneticDetachHysteresis
  }

  private func evaluateSnap(
    at point: CGPoint,
    in mapView: MLNMapView,
    theme: MarineTheme,
    currentlySnappedID: String?,
    snapCandidatesProvider: (MLNMapView) -> [WaypointSnapCandidate]
  ) -> WaypointSnapResult? {
    WaypointMagneticSnap.evaluate(
      reticlePoint: point,
      candidates: snapCandidatesProvider(mapView),
      currentlySnappedID: currentlySnappedID,
      attachRadius: magneticAttachRadius(for: theme),
      detachHysteresis: AppConstants.Map.waypointMagneticDetachHysteresis
    )
  }

  private func hasActiveMapTouchGesture(
    in mapView: MLNMapView,
    excluding excludedGestureRecognizer: UIGestureRecognizer?
  ) -> Bool {
    guard let recognizers = mapView.gestureRecognizers else { return false }
    return recognizers.contains { recognizer in
      guard recognizer !== excludedGestureRecognizer else { return false }
      return recognizer.state == .began || recognizer.state == .changed
    }
  }
}
