//
//  MeasureMapInteractionController.swift
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
import UIKit

/// Describes the vertical screen span occupied by the measure pins so the camera owner can frame them unobstructed.
struct MeasurePinVerticalFramingRequest: Equatable, Sendable {
  let minY: CGFloat
  let maxY: CGFloat
  let fallbackPoint: CGPoint
  let fallbackBottomOffset: CGFloat
}

/// Owns all gesture state, inverted-pin hit-testing, magnetic waypoint snapping, and framing requests
/// for the interactive nautical measurement tool. Never mutates `MLNMapView` camera directly.
@MainActor
final class MeasureMapInteractionController {

  private(set) var activeDraggedPin: ActiveMeasurePin?
  private(set) var isLongPressingPin: Bool = false
  private var snappedWaypointID: String?
  private var dragOffset: CGPoint = .zero
  private var lastPanUpdateTime: CFTimeInterval = 0
  private let snapFeedbackGenerator = UISelectionFeedbackGenerator()

  private static let panThrottleInterval: CFTimeInterval = 0.016

  // MARK: - Read-Only Interaction State

  var isDraggingPin: Bool {
    activeDraggedPin != nil
  }

  func isInteracting(measureViewModel: MeasureToolViewModel) -> Bool {
    activeDraggedPin != nil || isLongPressingPin || measureViewModel.isDraggingPin
  }

  func cancelActiveInteraction(measureViewModel: MeasureToolViewModel) {
    activeDraggedPin = nil
    isLongPressingPin = false
    snappedWaypointID = nil
    dragOffset = .zero
    if measureViewModel.isDraggingPin {
      measureViewModel.isDraggingPin = false
    }
  }

  // MARK: - Pure Testable Geometry (No MLNMapView Dependency)

  /// Computes the minimal Euclidean distance between `touchPoint` and an inverted nautical map pin
  /// (testing both the circular badge head below the tip and the needle tip itself).
  static func distanceToPin(
    touchPoint: CGPoint,
    tipPoint: CGPoint,
    needleToHeadCenterOffset: CGFloat = MarineMapPinShape.needleToHeadCenterOffset
  ) -> CGFloat {
    let headCenter = CGPoint(x: tipPoint.x, y: tipPoint.y + needleToHeadCenterOffset)
    let distHead = hypot(touchPoint.x - headCenter.x, touchPoint.y - headCenter.y)
    let distTip = hypot(touchPoint.x - tipPoint.x, touchPoint.y - tipPoint.y)
    return min(distHead, distTip)
  }

  /// Pure screen-space hit-test for Pins A and B.
  /// When both pins overlap within `hitRadius`, prioritizes the currently selected `activePin` so the user
  /// can separate stacked pins predictably without accidentally grabbing the inactive pin underneath.
  static func hitTestPin(
    at touchPoint: CGPoint,
    startTip: CGPoint,
    endTip: CGPoint,
    activePin: ActiveMeasurePin,
    hitRadius: CGFloat,
    needleToHeadCenterOffset: CGFloat = MarineMapPinShape.needleToHeadCenterOffset
  ) -> ActiveMeasurePin? {
    guard hitRadius >= 0 else { return nil }

    let minA = distanceToPin(
      touchPoint: touchPoint,
      tipPoint: startTip,
      needleToHeadCenterOffset: needleToHeadCenterOffset
    )
    let minB = distanceToPin(
      touchPoint: touchPoint,
      tipPoint: endTip,
      needleToHeadCenterOffset: needleToHeadCenterOffset
    )

    if minA <= hitRadius && minB <= hitRadius {
      return activePin
    } else if minA <= hitRadius {
      return .start
    } else if minB <= hitRadius {
      return .end
    }
    return nil
  }

  /// Clamps a screen point to the non-negative bounds `[0...width, 0...height]`.
  nonisolated static func clampPoint(_ point: CGPoint, to mapBounds: CGRect) -> CGPoint {
    CGPoint(
      x: min(max(point.x, 0), max(0, mapBounds.width)),
      y: min(max(point.y, 0), max(0, mapBounds.height))
    )
  }

  /// Builds the vertical framing envelope covering both pins A and B, prioritizing `activePin` as fallback if span exceeds viewport.
  static func makeFramingRequest(
    startTip: CGPoint,
    endTip: CGPoint,
    activePin: ActiveMeasurePin,
    pinHeight: CGFloat = MarinePinGraphicsFactory.pinHeight
  ) -> MeasurePinVerticalFramingRequest {
    let activePoint = (activePin == .start) ? startTip : endTip
    return MeasurePinVerticalFramingRequest(
      minY: min(startTip.y, endTip.y),
      maxY: max(startTip.y + pinHeight, endTip.y + pinHeight),
      fallbackPoint: activePoint,
      fallbackBottomOffset: pinHeight
    )
  }

  /// Pure screen-space vertical camera shift calculation fitting `[minY, maxY]` inside `visibleVerticalRange`.
  /// Accepts pre-resolved screen clearance bounds (`topClearance...bottomClearance`) rather than `sheetHeight`,
  /// keeping it independent of iPhone bottom sheets vs iPad lateral drawers.
  /// Returns `0` when the vertical shift is sub-point (`<= 1pt`).
  nonisolated static func verticalShiftToFitRange(
    minY: CGFloat,
    maxY: CGFloat,
    fallbackPointY: CGFloat?,
    fallbackBottomOffset: CGFloat,
    visibleVerticalRange: ClosedRange<CGFloat>
  ) -> CGFloat {
    let topClearance = visibleVerticalRange.lowerBound
    let targetBottomY = visibleVerticalRange.upperBound

    var deltaY: CGFloat = 0.0

    if maxY > targetBottomY {
      let neededShiftUp = maxY - targetBottomY
      if minY - neededShiftUp >= topClearance {
        deltaY = neededShiftUp
      } else if let fallbackY = fallbackPointY {
        let fallbackBottom = fallbackY + fallbackBottomOffset
        if fallbackBottom > targetBottomY {
          deltaY = fallbackBottom - targetBottomY
        } else if fallbackY < topClearance {
          deltaY = fallbackY - topClearance
        }
      }
    } else if minY < topClearance {
      let neededShiftDown = minY - topClearance
      if maxY - neededShiftDown <= targetBottomY {
        deltaY = neededShiftDown
      } else if let fallbackY = fallbackPointY {
        let fallbackBottom = fallbackY + fallbackBottomOffset
        if fallbackY < topClearance {
          deltaY = fallbackY - topClearance
        } else if fallbackBottom > targetBottomY {
          deltaY = fallbackBottom - targetBottomY
        }
      }
    }

    return abs(deltaY) > 1.0 ? deltaY : 0.0
  }

  // MARK: - MapLibre Projection & Gesture Handling

  func hitTestPin(
    at point: CGPoint,
    in mapView: MLNMapView,
    measureViewModel: MeasureToolViewModel,
    hitRadius: CGFloat
  ) -> ActiveMeasurePin? {
    guard measureViewModel.isActive,
          let startCoord = measureViewModel.startCoordinate,
          let endCoord = measureViewModel.endCoordinate else {
      return nil
    }
    let ptA = mapView.convert(startCoord, toPointTo: mapView)
    let ptB = mapView.convert(endCoord, toPointTo: mapView)
    return Self.hitTestPin(
      at: point,
      startTip: ptA,
      endTip: ptB,
      activePin: measureViewModel.activePin,
      hitRadius: hitRadius
    )
  }

  func shouldBeginPan(
    at touchPoint: CGPoint,
    in mapView: MLNMapView,
    measureViewModel: MeasureToolViewModel,
    hitRadius: CGFloat
  ) -> Bool {
    hitTestPin(
      at: touchPoint,
      in: mapView,
      measureViewModel: measureViewModel,
      hitRadius: hitRadius
    ) != nil
  }

  func handleTap(
    _ sender: UITapGestureRecognizer,
    in mapView: MLNMapView,
    measureViewModel: MeasureToolViewModel,
    hitRadius: CGFloat,
    onUserInteraction: () -> Void
  ) {
    guard sender.state == .ended, measureViewModel.isActive else { return }
    onUserInteraction()
    let point = sender.location(in: mapView)
    if let hitPin = hitTestPin(
      at: point,
      in: mapView,
      measureViewModel: measureViewModel,
      hitRadius: hitRadius
    ) {
      measureViewModel.activePin = hitPin
      return
    }
    let coord = mapView.convert(point, toCoordinateFrom: mapView)
    measureViewModel.handleMapTap(at: coord)
  }

  func handlePan(
    _ sender: UIPanGestureRecognizer,
    in mapView: MLNMapView,
    measureViewModel: MeasureToolViewModel,
    hitRadius: CGFloat,
    attachRadius: CGFloat,
    snapCandidatesProvider: (MLNMapView) -> [WaypointSnapCandidate],
    onUserInteraction: () -> Void,
    onRequestVerticalFraming: (MeasurePinVerticalFramingRequest, CGFloat) -> Void
  ) {
    let touchPoint = sender.location(in: mapView)

    switch sender.state {
    case .began:
      guard let pin = hitTestPin(
        at: touchPoint,
        in: mapView,
        measureViewModel: measureViewModel,
        hitRadius: hitRadius
      ) else {
        return
      }
      activeDraggedPin = pin
      measureViewModel.activePin = pin
      measureViewModel.isDraggingPin = true
      onUserInteraction()
      snapFeedbackGenerator.prepare()

      let currentCoord = (pin == .start)
        ? measureViewModel.startCoordinate
        : measureViewModel.endCoordinate
      if let currentCoord {
        let tipPoint = mapView.convert(currentCoord, toPointTo: mapView)
        dragOffset = CGPoint(
          x: touchPoint.x - tipPoint.x,
          y: touchPoint.y - tipPoint.y
        )
        // Seed hysteresis only if the pin is actually resting on a waypoint (<= 1pt),
        // so zooming out near an open-water pin never causes a false lock on grab.
        snappedWaypointID = WaypointMagneticSnap.evaluate(
          reticlePoint: tipPoint,
          candidates: snapCandidatesProvider(mapView),
          currentlySnappedID: nil,
          attachRadius: 1.0,
          detachHysteresis: 0
        )?.waypointID
      } else {
        dragOffset = .zero
        snappedWaypointID = nil
      }
      lastPanUpdateTime = CACurrentMediaTime()

    case .changed:
      guard let pin = activeDraggedPin else { return }
      guard measureViewModel.isActive else {
        cancelActiveInteraction(measureViewModel: measureViewModel)
        return
      }

      let now = CACurrentMediaTime()
      guard now - lastPanUpdateTime >= Self.panThrottleInterval else { return }
      lastPanUpdateTime = now

      let rawTip = CGPoint(
        x: touchPoint.x - dragOffset.x,
        y: touchPoint.y - dragOffset.y
      )
      let clampedTip = Self.clampPoint(rawTip, to: mapView.bounds)
      let coord = resolvePinCoordinate(
        for: clampedTip,
        in: mapView,
        attachRadius: attachRadius,
        snapCandidatesProvider: snapCandidatesProvider
      )
      updatePin(pin, to: coord, in: measureViewModel)

    case .ended:
      if let pin = activeDraggedPin, measureViewModel.isActive {
        let rawTip = CGPoint(
          x: touchPoint.x - dragOffset.x,
          y: touchPoint.y - dragOffset.y
        )
        let clampedTip = Self.clampPoint(rawTip, to: mapView.bounds)
        let coord = resolvePinCoordinate(
          for: clampedTip,
          in: mapView,
          attachRadius: attachRadius,
          snapCandidatesProvider: snapCandidatesProvider
        )
        updatePin(pin, to: coord, in: measureViewModel)
      }
      activeDraggedPin = nil
      snappedWaypointID = nil
      dragOffset = .zero
      measureViewModel.isDraggingPin = false
      requestEnsureVisibleIfNeeded(
        in: mapView,
        measureViewModel: measureViewModel,
        sheetHeight: measureViewModel.lastSheetHeight,
        onRequestVerticalFraming: onRequestVerticalFraming
      )

    case .cancelled, .failed:
      activeDraggedPin = nil
      snappedWaypointID = nil
      dragOffset = .zero
      measureViewModel.isDraggingPin = false
      requestEnsureVisibleIfNeeded(
        in: mapView,
        measureViewModel: measureViewModel,
        sheetHeight: measureViewModel.lastSheetHeight,
        onRequestVerticalFraming: onRequestVerticalFraming
      )

    default:
      break
    }
  }

  func handleLongPress(
    _ sender: UILongPressGestureRecognizer,
    in mapView: MLNMapView,
    measureViewModel: MeasureToolViewModel,
    attachRadius: CGFloat,
    snapCandidatesProvider: (MLNMapView) -> [WaypointSnapCandidate],
    onUserInteraction: () -> Void,
    onRequestVerticalFraming: (MeasurePinVerticalFramingRequest, CGFloat) -> Void
  ) {
    guard measureViewModel.isActive else {
      cancelActiveInteraction(measureViewModel: measureViewModel)
      return
    }

    let touchPoint = sender.location(in: mapView)
    // Technical Design Choice: Offset so the circular round head arrives directly under the user's finger,
    // leaving the needle tip pointing above the finger for full chart feature visibility.
    let tipPoint = CGPoint(
      x: touchPoint.x,
      y: touchPoint.y - MarineMapPinShape.needleToHeadCenterOffset
    )
    let clampedTip = Self.clampPoint(tipPoint, to: mapView.bounds)

    switch sender.state {
    case .began:
      measureViewModel.isDraggingPin = true
      isLongPressingPin = true
      snappedWaypointID = nil
      snapFeedbackGenerator.prepare()
      onUserInteraction()
      let coord = resolvePinCoordinate(
        for: clampedTip,
        in: mapView,
        attachRadius: attachRadius,
        snapCandidatesProvider: snapCandidatesProvider
      )
      measureViewModel.handleMapLongPress(at: coord)
      lastPanUpdateTime = CACurrentMediaTime()

    case .changed:
      let now = CACurrentMediaTime()
      guard now - lastPanUpdateTime >= Self.panThrottleInterval else { return }
      lastPanUpdateTime = now

      onUserInteraction()
      let coord = resolvePinCoordinate(
        for: clampedTip,
        in: mapView,
        attachRadius: attachRadius,
        snapCandidatesProvider: snapCandidatesProvider
      )
      measureViewModel.handleMapLongPress(at: coord)

    case .ended:
      onUserInteraction()
      let coord = resolvePinCoordinate(
        for: clampedTip,
        in: mapView,
        attachRadius: attachRadius,
        snapCandidatesProvider: snapCandidatesProvider
      )
      measureViewModel.handleMapLongPress(at: coord)
      snappedWaypointID = nil
      measureViewModel.isDraggingPin = false
      isLongPressingPin = false
      requestEnsureVisibleIfNeeded(
        in: mapView,
        measureViewModel: measureViewModel,
        sheetHeight: measureViewModel.lastSheetHeight,
        onRequestVerticalFraming: onRequestVerticalFraming
      )

    case .cancelled, .failed:
      snappedWaypointID = nil
      measureViewModel.isDraggingPin = false
      isLongPressingPin = false
      requestEnsureVisibleIfNeeded(
        in: mapView,
        measureViewModel: measureViewModel,
        sheetHeight: measureViewModel.lastSheetHeight,
        onRequestVerticalFraming: onRequestVerticalFraming
      )

    default:
      break
    }
  }

  func requestEnsureVisibleIfNeeded(
    in mapView: MLNMapView,
    measureViewModel: MeasureToolViewModel,
    sheetHeight: CGFloat,
    onRequestVerticalFraming: (MeasurePinVerticalFramingRequest, CGFloat) -> Void
  ) {
    guard measureViewModel.isActive,
          let startCoord = measureViewModel.startCoordinate,
          let endCoord = measureViewModel.endCoordinate else {
      return
    }

    let ptA = mapView.convert(startCoord, toPointTo: mapView)
    let ptB = mapView.convert(endCoord, toPointTo: mapView)
    let request = Self.makeFramingRequest(
      startTip: ptA,
      endTip: ptB,
      activePin: measureViewModel.activePin
    )
    onRequestVerticalFraming(request, sheetHeight)
  }

  // MARK: - Private Helpers

  private func updatePin(
    _ pin: ActiveMeasurePin,
    to coordinate: CLLocationCoordinate2D,
    in measureViewModel: MeasureToolViewModel
  ) {
    switch pin {
    case .start:
      measureViewModel.updateStart(to: coordinate)
    case .end:
      measureViewModel.updateEnd(to: coordinate)
    }
  }

  private func resolvePinCoordinate(
    for tipPoint: CGPoint,
    in mapView: MLNMapView,
    attachRadius: CGFloat,
    snapCandidatesProvider: (MLNMapView) -> [WaypointSnapCandidate]
  ) -> CLLocationCoordinate2D {
    if let snap = WaypointMagneticSnap.evaluate(
      reticlePoint: tipPoint,
      candidates: snapCandidatesProvider(mapView),
      currentlySnappedID: snappedWaypointID,
      attachRadius: attachRadius,
      detachHysteresis: AppConstants.Map.waypointMagneticDetachHysteresis
    ) {
      if snap.waypointID != snappedWaypointID {
        snapFeedbackGenerator.selectionChanged()
      }
      snappedWaypointID = snap.waypointID
      return snap.coordinate
    } else {
      snappedWaypointID = nil
      return mapView.convert(tipPoint, toCoordinateFrom: mapView)
    }
  }
}
