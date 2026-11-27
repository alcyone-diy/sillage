//
//  MapCameraController.swift
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
import OSLog
import UIKit

/// Snapshot of the MapLibre camera captured prior to a forced style reload (e.g. `networkDidReconnect`).
struct SavedMapCameraSnapshot: Equatable, Sendable {
  let center: CLLocationCoordinate2D
  let zoomLevel: Double
  let direction: CLLocationDirection
}

/// Exclusive owner of all `MLNMapView` camera mutations (`setCenter`, `setCamera`, `setVisibleCoordinateBounds`),
/// `contentInset` management, `cameraMoveStream` consumption, and rough-sea tracking tolerance margins.
@MainActor
final class MapCameraController {

  private var streamTask: TaskCancellable?

  private(set) var lastTrackingMode: ChartTrackingMode = .free
  private(set) var lastBounds: CGRect = .zero
  private(set) var hasAppliedInitialCamera: Bool = false
  private(set) var pendingReloadCamera: SavedMapCameraSnapshot?

  /// Technical Design Choice: Vessel Centering Gesture Tolerance Margin
  /// Tracks the initial anchor coordinate and screen point at the start of a manual drag gesture,
  /// allowing accidental touches, slips, and small vibrations to be tolerated without immediately breaking tracking mode.
  private(set) var initialPanCenterCoordinate: CLLocationCoordinate2D?
  private(set) var initialPanScreenPoint: CGPoint?
  private(set) var hasExceededTrackingMargin: Bool = false

  func cancelTasks() {
    streamTask?.cancel()
    streamTask = nil
  }

  // MARK: - Pure Testable Camera & Viewport Geometry (No MLNMapView Dependency)

  nonisolated static func isZoomReason(_ reason: MLNCameraChangeReason) -> Bool {
    reason.contains(.gesturePinch) ||
    reason.contains(.gestureZoomIn) ||
    reason.contains(.gestureZoomOut) ||
    reason.contains(.gestureOneFingerZoom)
  }

  nonisolated static func shouldBreakTracking(for reason: MLNCameraChangeReason) -> Bool {
    let isZooming = isZoomReason(reason)
    let isPanningOrRotating = reason.contains(.gesturePan) || reason.contains(.gestureRotate)
    // Break tracking ONLY if panning/rotating and NOT zooming
    return isPanningOrRotating && !isZooming
  }

  nonisolated static func hasExceededTrackingBreakThreshold(
    from initialScreenPoint: CGPoint,
    to currentScreenPoint: CGPoint,
    isGloveMode: Bool
  ) -> Bool {
    let displacement = hypot(
      currentScreenPoint.x - initialScreenPoint.x,
      currentScreenPoint.y - initialScreenPoint.y
    )
    let threshold = isGloveMode
      ? AppConstants.Map.trackingBreakGloveThreshold
      : AppConstants.Map.trackingBreakThreshold
    return displacement >= threshold
  }

  /// Computes the look-ahead top `contentInset` for `.courseUp` tracking, returning `.zero` in all other modes or on empty bounds.
  nonisolated static func courseUpContentInset(
    for bounds: CGRect,
    trackingMode: ChartTrackingMode
  ) -> UIEdgeInsets {
    guard trackingMode == .courseUp, bounds.height > 0 else {
      return .zero
    }
    return UIEdgeInsets(top: bounds.height / 3.0, left: 0, bottom: 0, right: 0)
  }

  /// Pure screen-space offset math returning the new screen point where the current camera center must move
  /// so that a coordinate currently at `currentCoordScreenPoint` lands at `targetScreenPoint`.
  nonisolated static func centerScreenPointForTarget(
    _ currentCoordScreenPoint: CGPoint,
    toAppearAt targetScreenPoint: CGPoint,
    currentCenterScreenPoint: CGPoint
  ) -> CGPoint {
    let deltaX = currentCoordScreenPoint.x - targetScreenPoint.x
    let deltaY = currentCoordScreenPoint.y - targetScreenPoint.y
    return CGPoint(
      x: currentCenterScreenPoint.x + deltaX,
      y: currentCenterScreenPoint.y + deltaY
    )
  }

  /// Computes the unobstructed screen rectangle used by `isCoordinateVisible`.
  nonisolated static func visibleContentRect(
    in bounds: CGRect,
    topSafeAreaInset: CGFloat,
    sheetClearance: CGFloat = 240.0
  ) -> CGRect {
    CGRect(
      x: 0,
      y: topSafeAreaInset,
      width: bounds.width,
      height: max(50.0, bounds.height - sheetClearance - topSafeAreaInset)
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

  // MARK: - Testable Reload & Tracking Tolerance State Transitions

  /// Records that the initial boot camera has been applied so subsequent style reloads preserve live camera state.
  func markInitialCameraApplied() {
    hasAppliedInitialCamera = true
  }

  /// Stores a pre-reload camera snapshot if the initial camera was already applied.
  func captureReloadCamera(_ snapshot: SavedMapCameraSnapshot) {
    guard hasAppliedInitialCamera else { return }
    pendingReloadCamera = snapshot
  }

  /// Atomically consumes and clears any saved pre-reload camera snapshot.
  func consumePendingReloadCamera() -> SavedMapCameraSnapshot? {
    let saved = pendingReloadCamera
    pendingReloadCamera = nil
    return saved
  }

  /// Updates `lastBounds` and returns `true` when the viewport size has changed.
  func consumeBoundsSizeChange(_ newBounds: CGRect) -> Bool {
    guard lastBounds.size != newBounds.size else { return false }
    lastBounds = newBounds
    return true
  }

  func beginTrackingPanEvaluation(coordinate: CLLocationCoordinate2D, screenPoint: CGPoint) {
    initialPanCenterCoordinate = coordinate
    initialPanScreenPoint = screenPoint
    hasExceededTrackingMargin = false
  }

  /// Evaluates whether the panned anchor point has crossed the rough-sea tolerance margin, latching `hasExceededTrackingMargin`.
  func evaluateTrackingDisplacement(currentScreenPoint: CGPoint, isGloveMode: Bool) -> Bool {
    guard !hasExceededTrackingMargin, let initialPoint = initialPanScreenPoint else {
      return false
    }
    if Self.hasExceededTrackingBreakThreshold(
      from: initialPoint,
      to: currentScreenPoint,
      isGloveMode: isGloveMode
    ) {
      hasExceededTrackingMargin = true
      return true
    }
    return false
  }

  func resetTrackingPanEvaluation() {
    initialPanCenterCoordinate = nil
    initialPanScreenPoint = nil
    hasExceededTrackingMargin = false
  }

  // MARK: - Centralized MLNMapView Camera Commands

  func applyInitialViewportCamera(from viewModel: ChartViewModel, in mapView: MLNMapView) {
    mapView.setCenter(
      viewModel.centerCoordinate,
      zoomLevel: viewModel.zoomLevel,
      direction: viewModel.chartDirection.converted(to: .degrees).value,
      animated: false
    )
  }

  func syncCameraAfterChartSourceSwitch(from viewModel: ChartViewModel, in mapView: MLNMapView) {
    applyInitialViewportCamera(from: viewModel, in: mapView)
  }

  /// Resets heading (`0°`) and pitch (`0°`) in a single non-animated camera transaction when deviated.
  func resetToNorthUpLevelIfNeeded(in mapView: MLNMapView) {
    guard mapView.direction != 0 || mapView.camera.pitch != 0 else { return }
    let camera = mapView.camera
    camera.heading = 0
    camera.pitch = 0
    mapView.setCamera(camera, animated: false)
  }

  func syncOfflineSelectionRotationLock(isSelectionModeActive: Bool, in mapView: MLNMapView) {
    if isSelectionModeActive {
      mapView.isRotateEnabled = false
      // Restore North-Up orientation and level pitch immediately without animation.
      // Mathematical integrity: animated transitions cause mapView.convert() to project against
      // a transient tilted/rotated perspective, producing corrupted coordinates.
      resetToNorthUpLevelIfNeeded(in: mapView)
    } else {
      mapView.isRotateEnabled = true
    }
  }

  func syncTrackingModeAndContentInset(
    trackingMode: ChartTrackingMode,
    in mapView: MLNMapView,
    delegate: MLNMapViewDelegate
  ) {
    // Stop inertia cleanly when locking tracking mode without triggering delegate events
    if lastTrackingMode != trackingMode {
      if lastTrackingMode == .free && trackingMode != .free {
        mapView.delegate = nil
        mapView.setCamera(mapView.camera, animated: false)
        mapView.delegate = delegate
      }
      lastTrackingMode = trackingMode
    }

    if mapView.userTrackingMode != .none {
      mapView.userTrackingMode = .none
    }

    let newInset = Self.courseUpContentInset(for: mapView.bounds, trackingMode: trackingMode)
    if mapView.contentInset != newInset {
      mapView.setContentInset(newInset, animated: true, completionHandler: nil)
    }

    mapView.compassView.isUserInteractionEnabled = (trackingMode != .courseUp)
  }

  func enforceDisabledNativeUserTracking(on mapView: MLNMapView, mode: MLNUserTrackingMode) {
    guard mode != .none else { return }
    Task { @MainActor [weak mapView] in
      guard let mapView, mapView.userTrackingMode != .none else { return }
      mapView.userTrackingMode = .none
    }
  }

  func isCoordinateVisible(_ coordinate: CLLocationCoordinate2D, in mapView: MLNMapView) -> Bool {
    let pt = mapView.convert(coordinate, toPointTo: mapView)
    let visibleRect = Self.visibleContentRect(
      in: mapView.bounds,
      topSafeAreaInset: mapView.safeAreaInsets.top
    )
    return visibleRect.contains(pt)
  }

  /// Pure geometric projection computing the camera center coordinate required for `coordinate` to appear at `targetPoint` on screen.
  func centerCoordinateToPosition(
    _ coordinate: CLLocationCoordinate2D,
    at targetPoint: CGPoint,
    in mapView: MLNMapView
  ) -> CLLocationCoordinate2D {
    let currentCoordPoint = mapView.convert(coordinate, toPointTo: mapView)
    let currentCenterPoint = mapView.convert(mapView.centerCoordinate, toPointTo: mapView)
    let newCenterPoint = Self.centerScreenPointForTarget(
      currentCoordPoint,
      toAppearAt: targetPoint,
      currentCenterScreenPoint: currentCenterPoint
    )
    return mapView.convert(newCenterPoint, toCoordinateFrom: mapView)
  }

  /// Synchronously centers the map so `coordinate` lands at `targetPoint` on screen.
  /// Preserves delegate attachment so callers (such as `CalloutAimingController`) receive synchronous cancellation
  /// and completion `regionDidChangeWith` callbacks as expected.
  func centerCoordinate(
    _ coordinate: CLLocationCoordinate2D,
    atScreenPoint targetPoint: CGPoint,
    in mapView: MLNMapView,
    resetContentInset: Bool,
    animated: Bool
  ) {
    if resetContentInset && mapView.contentInset != .zero {
      mapView.contentInset = .zero
    }
    let newCenterCoordinate = centerCoordinateToPosition(coordinate, at: targetPoint, in: mapView)
    mapView.setCenter(newCenterCoordinate, animated: animated)
  }

  /// Shifts the map camera vertically so `[minY, maxY]` fits comfortably between the top HUD clearance and bottom sheet.
  func shiftToFitVerticalRange(
    minY: CGFloat,
    maxY: CGFloat,
    fallbackPoint: CGPoint?,
    fallbackBottomOffset: CGFloat? = nil,
    in mapView: MLNMapView,
    sheetHeight: CGFloat,
    isGloveMode: Bool
  ) {
    let safeBottom = mapView.safeAreaInsets.bottom
    let marginAboveSheet: CGFloat = 24.0
    let topClearance: CGFloat = max(mapView.safeAreaInsets.top + 80.0, MarineTheme.Metrics.topToolbarClearance)

    let effectiveSheetHeight = sheetHeight > 0 ? sheetHeight : (isGloveMode ? 260.0 : 220.0)
    let dialogTopY = mapView.bounds.height - effectiveSheetHeight - safeBottom
    let targetPinBottomY = max(topClearance, dialogTopY - marginAboveSheet)
    let effectiveFallbackOffset = fallbackBottomOffset ?? MarinePinGraphicsFactory.pinHeight

    let deltaY = Self.verticalShiftToFitRange(
      minY: minY,
      maxY: maxY,
      fallbackPointY: fallbackPoint?.y,
      fallbackBottomOffset: effectiveFallbackOffset,
      visibleVerticalRange: topClearance...targetPinBottomY
    )

    if deltaY != 0.0 {
      let currentCenterPoint = mapView.convert(mapView.centerCoordinate, toPointTo: mapView)
      let newCenterPoint = CGPoint(x: currentCenterPoint.x, y: currentCenterPoint.y + deltaY)
      let newCenterCoordinate = mapView.convert(newCenterPoint, toCoordinateFrom: mapView)
      mapView.setCenter(newCenterCoordinate, animated: true)
    }
  }

  // MARK: - Style Reload Camera Capture & Restoration

  func captureReloadCameraIfNeeded(from mapView: MLNMapView) {
    captureReloadCamera(
      SavedMapCameraSnapshot(
        center: mapView.centerCoordinate,
        zoomLevel: mapView.zoomLevel,
        direction: mapView.direction
      )
    )
  }

  func restoreCameraAfterStyleLoad(from viewModel: ChartViewModel, in mapView: MLNMapView) {
    if let savedCamera = consumePendingReloadCamera() {
      mapView.setCenter(
        savedCamera.center,
        zoomLevel: savedCamera.zoomLevel,
        direction: savedCamera.direction,
        animated: false
      )
    } else if !hasAppliedInitialCamera {
      markInitialCameraApplied()
      applyInitialViewportCamera(from: viewModel, in: mapView)
    }
  }

  // MARK: - Camera Stream Subscription

  func startCameraStreamSubscription(for mapView: MLNMapView, viewModel: ChartViewModel) {
    streamTask?.cancel()
    let stream = viewModel.cameraMoveStream
    streamTask = TaskCancellable(Task { @MainActor [weak self, weak mapView, weak viewModel] in
      for await event in stream {
        guard !Task.isCancelled, let self, let mapView, let viewModel else { break }
        self.applyCameraMoveEvent(event, in: mapView, viewModel: viewModel)
      }
    })
  }

  /// Synchronously dispatches a camera command to MapLibre so newer GPS / user camera events
  /// immediately interrupt in-flight animations instead of queueing behind suspended `await` frames.
  private func applyCameraMoveEvent(
    _ event: CameraMoveEvent,
    in mapView: MLNMapView,
    viewModel: ChartViewModel
  ) {
    switch event {
    case .fitBounds(let bounds, let padding, let animated):
      let mlnBounds = MLNCoordinateBounds(sw: bounds.southWest, ne: bounds.northEast)
      mapView.setVisibleCoordinateBounds(mlnBounds, edgePadding: padding, animated: animated, completionHandler: nil)
    case .center(let coordinate, let zoom, let heading):
      let targetZoom = zoom ?? mapView.zoomLevel
      if let heading {
        mapView.setCenter(
          coordinate,
          zoomLevel: targetZoom,
          direction: heading.converted(to: .degrees).value,
          animated: true,
          completionHandler: nil
        )
      } else {
        mapView.setCenter(coordinate, zoomLevel: targetZoom, animated: true)
      }
    case .positionAtScreenFraction(let coordinate, let yFraction, let xFraction):
      guard mapView.bounds.height > 0, mapView.bounds.width > 0 else {
        mapView.setCenter(coordinate, animated: true)
        break
      }
      let targetPoint = CGPoint(
        x: mapView.bounds.width * xFraction,
        y: mapView.bounds.height * yFraction
      )
      centerCoordinate(
        coordinate,
        atScreenPoint: targetPoint,
        in: mapView,
        resetContentInset: viewModel.trackingMode != .courseUp,
        animated: true
      )
    }
  }

  // MARK: - Region Change Lifecycle

  func regionWillChange(
    in mapView: MLNMapView,
    reason: MLNCameraChangeReason,
    viewModel: ChartViewModel
  ) {
    guard !reason.contains(.programmatic) else { return }
    viewModel.isMapMoving = true

    guard viewModel.trackingMode != .free,
          !viewModel.anchorViewModel.isAdjustingAnchor,
          viewModel.waypointAdjustmentSession == nil else {
      return
    }

    if Self.shouldBreakTracking(for: reason) {
      beginTrackingPanEvaluation(
        coordinate: mapView.centerCoordinate,
        screenPoint: mapView.convert(mapView.centerCoordinate, toPointTo: mapView)
      )
    } else {
      resetTrackingPanEvaluation()
    }
  }

  func regionIsChanging(
    in mapView: MLNMapView,
    viewModel: ChartViewModel,
    isGloveMode: Bool
  ) {
    let mpp = mapView.metersPerPoint(atLatitude: mapView.centerCoordinate.latitude)
    viewModel.throttledUpdateMapScaleAndZoom(metersPerPoint: mpp, zoomLevel: mapView.zoomLevel)
    viewModel.throttledUpdateCenterCoordinate(mapView.centerCoordinate)
    viewModel.updateOfflineRegionScreenPositions(
      projection: { mapView.convert($0, toPointTo: mapView) },
      bounds: mapView.bounds
    )

    if viewModel.trackingMode != .free,
       !viewModel.anchorViewModel.isAdjustingAnchor,
       viewModel.waypointAdjustmentSession == nil,
       let initialCoord = initialPanCenterCoordinate {
      let currentPoint = mapView.convert(initialCoord, toPointTo: mapView)
      if evaluateTrackingDisplacement(currentScreenPoint: currentPoint, isGloveMode: isGloveMode) {
        viewModel.chartInteractedByUser()
      }
    }
  }

  func regionDidChange(
    in mapView: MLNMapView,
    reason: MLNCameraChangeReason,
    viewModel: ChartViewModel
  ) {
    viewModel.isMapMoving = false

    Task { @MainActor [weak self, weak mapView, weak viewModel] in
      guard let self, let mapView, let viewModel else { return }

      let mpp = mapView.metersPerPoint(atLatitude: mapView.centerCoordinate.latitude)
      viewModel.updateMapScaleAndZoomImmediately(metersPerPoint: mpp, zoomLevel: mapView.zoomLevel)
      viewModel.updateCenterCoordinateImmediately(mapView.centerCoordinate)
      viewModel.chartDirection = Measurement(value: mapView.direction, unit: UnitAngle.degrees)
      viewModel.saveCameraState()

      let visibleBounds = mapView.visibleCoordinateBounds
      viewModel.currentVisibleBounds = GeographicBoundingBox(
        southWest: visibleBounds.sw,
        northEast: visibleBounds.ne
      )

      viewModel.updateOfflineRegionScreenPositions(
        projection: { mapView.convert($0, toPointTo: mapView) },
        bounds: mapView.bounds
      )

      if viewModel.trackingMode != .free {
        if self.hasExceededTrackingMargin {
          viewModel.chartInteractedByUser()
        } else if Self.shouldBreakTracking(for: reason) {
          if !viewModel.anchorViewModel.isAdjustingAnchor &&
             viewModel.waypointAdjustmentSession == nil &&
             !viewModel.calloutViewModel.isCalloutVisible {
            Logger.chart.info("Manual drag remained within tolerance margin; recentering on vessel.")
            viewModel.centerOnUserLocation()
          }
        }
      }

      self.resetTrackingPanEvaluation()
    }
  }
}
