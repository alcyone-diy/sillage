//
//  OfflineSelectionInteractionController.swift
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

/// Identifies the 4 draggable corner handles of the offline chart selection rectangle.
enum ActiveSelectionCorner: Equatable, Sendable, CaseIterable {
  case topLeft      // NW
  case topRight     // NE
  case bottomLeft   // SW
  case bottomRight  // SE
}

/// Screen-projected coordinates of the 4 selection corners for pure geometric hit-testing.
struct ProjectedSelectionCorners: Equatable, Sendable {
  let topLeft: CGPoint
  let topRight: CGPoint
  let bottomRight: CGPoint
  let bottomLeft: CGPoint
}

/// Owns all interactive state, pure geometry, and corner-dragging gestures for the Offline Chart Selection mode.
/// Never mutates the MapLibre camera directly; camera orientation prerequisites remain owned by the camera layer.
@MainActor
final class OfflineSelectionInteractionController {

  private let styleSynchronizer: MapStyleStateSynchronizer

  private(set) var activeDraggedCorner: ActiveSelectionCorner?
  private var dragInitialBounds: GeographicBoundingBox?
  private var dragCurrentBounds: GeographicBoundingBox?
  private var lastPanUpdateTime: CFTimeInterval = 0

  private static let panThrottleInterval: CFTimeInterval = 0.016

  init(styleSynchronizer: MapStyleStateSynchronizer) {
    self.styleSynchronizer = styleSynchronizer
  }

  // MARK: - Read-Only Interaction State

  var isDraggingCorner: Bool {
    activeDraggedCorner != nil
  }

  var isInteracting: Bool {
    activeDraggedCorner != nil
  }

  /// Resolves the effective selection bounding box to render, prioritizing an in-flight corner drag
  /// so 1 Hz GPS updates never snap the visual rectangle back to uncommitted bounds mid-gesture.
  func resolvedBounds(
    isSelectionModeActive: Bool,
    committedBounds: GeographicBoundingBox?
  ) -> GeographicBoundingBox? {
    guard isSelectionModeActive else { return nil }
    return dragCurrentBounds ?? committedBounds
  }

  // MARK: - Pure Testable Geometry (No MLNMapView Dependency)

  /// Computes the centered default selection crop rectangle inside `viewportBounds`.
  nonisolated static func defaultCropRect(
    in viewportBounds: CGRect,
    widthRatio: CGFloat,
    aspect: CGFloat
  ) -> CGRect? {
    guard viewportBounds.width > 0, viewportBounds.height > 0, widthRatio > 0, aspect > 0 else {
      return nil
    }
    let baseSize = min(viewportBounds.width, viewportBounds.height) * widthRatio
    let size = CGSize(width: baseSize, height: baseSize * aspect)
    return CGRect(
      x: viewportBounds.minX + (viewportBounds.width - size.width) / 2.0,
      y: viewportBounds.minY + (viewportBounds.height - size.height) / 2.0,
      width: size.width,
      height: size.height
    )
  }

  /// Pure screen-space hit-test returning the closest corner handle within `hitRadius`, or `nil` if out of range.
  nonisolated static func hitTestCorner(
    at touchPoint: CGPoint,
    corners: ProjectedSelectionCorners,
    hitRadius: CGFloat
  ) -> ActiveSelectionCorner? {
    guard hitRadius >= 0 else { return nil }

    let candidates: [(ActiveSelectionCorner, CGFloat)] = [
      (.topLeft, hypot(touchPoint.x - corners.topLeft.x, touchPoint.y - corners.topLeft.y)),
      (.topRight, hypot(touchPoint.x - corners.topRight.x, touchPoint.y - corners.topRight.y)),
      (.bottomRight, hypot(touchPoint.x - corners.bottomRight.x, touchPoint.y - corners.bottomRight.y)),
      (.bottomLeft, hypot(touchPoint.x - corners.bottomLeft.x, touchPoint.y - corners.bottomLeft.y))
    ]

    guard let closest = candidates.min(by: { $0.1 < $1.1 }), closest.1 <= hitRadius else {
      return nil
    }
    return closest.0
  }

  /// Computes the updated geographic bounding box when dragging `corner` to `coord`,
  /// enforcing `minimumSelectionSpan` (500 m) along both axes with `cos(latitude)` Mercator foreshortening compensation.
  nonisolated static func computeUpdatedBounds(
    from current: GeographicBoundingBox,
    dragging corner: ActiveSelectionCorner,
    to coord: CLLocationCoordinate2D
  ) -> GeographicBoundingBox {
    let earthRadiusMeters = GeodesicConstants.earthMeanRadius.converted(to: .meters).value
    let minMeters = AppConstants.Cartography.Offline.minimumSelectionSpan.converted(to: .meters).value
    let minLatSpan = Measurement(value: minMeters / earthRadiusMeters, unit: UnitAngle.radians)
      .converted(to: .degrees).value
    let midLatRadians = Measurement(value: current.center.latitude, unit: UnitAngle.degrees)
      .converted(to: .radians).value
    let cosLat = max(abs(cos(midLatRadians)), 0.01)
    let minLonSpan = minLatSpan / cosLat

    var sw = current.southWest
    var ne = current.northEast

    switch corner {
    case .topLeft: // NW: updates latitude of North, longitude of West
      ne.latitude = max(coord.latitude, sw.latitude + minLatSpan)
      sw.longitude = min(coord.longitude, ne.longitude - minLonSpan)
    case .topRight: // NE: updates latitude of North, longitude of East
      ne.latitude = max(coord.latitude, sw.latitude + minLatSpan)
      ne.longitude = max(coord.longitude, sw.longitude + minLonSpan)
    case .bottomLeft: // SW: updates latitude of South, longitude of West
      sw.latitude = min(coord.latitude, ne.latitude - minLatSpan)
      sw.longitude = min(coord.longitude, ne.longitude - minLonSpan)
    case .bottomRight: // SE: updates latitude of South, longitude of East
      sw.latitude = min(coord.latitude, ne.latitude - minLatSpan)
      ne.longitude = max(coord.longitude, sw.longitude + minLonSpan)
    }

    return GeographicBoundingBox(southWest: sw, northEast: ne)
  }

  // MARK: - MapLibre Projection & Gesture Handling

  /// Projects the default centered crop box onto the current North-Up map viewport without mutating the camera.
  func makeDefaultBounds(
    in mapView: MLNMapView,
    cropBoxWidthRatio: CGFloat,
    cropBoxAspect: CGFloat
  ) -> GeographicBoundingBox? {
    guard let rect = Self.defaultCropRect(
      in: mapView.bounds,
      widthRatio: cropBoxWidthRatio,
      aspect: cropBoxAspect
    ) else {
      return nil
    }
    let mlnBounds = mapView.convert(rect, toCoordinateBoundsFrom: mapView)
    return GeographicBoundingBox(southWest: mlnBounds.sw, northEast: mlnBounds.ne)
  }

  func hitTestCorner(
    at point: CGPoint,
    in mapView: MLNMapView,
    offlineViewModel: OfflineSelectionViewModel,
    hitRadius: CGFloat
  ) -> ActiveSelectionCorner? {
    guard offlineViewModel.isSelectionModeActive,
          let bounds = offlineViewModel.selectedBounds else {
      return nil
    }

    let nw = CLLocationCoordinate2D(latitude: bounds.northEast.latitude, longitude: bounds.southWest.longitude)
    let ne = CLLocationCoordinate2D(latitude: bounds.northEast.latitude, longitude: bounds.northEast.longitude)
    let se = CLLocationCoordinate2D(latitude: bounds.southWest.latitude, longitude: bounds.northEast.longitude)
    let sw = CLLocationCoordinate2D(latitude: bounds.southWest.latitude, longitude: bounds.southWest.longitude)

    let projected = ProjectedSelectionCorners(
      topLeft: mapView.convert(nw, toPointTo: mapView),
      topRight: mapView.convert(ne, toPointTo: mapView),
      bottomRight: mapView.convert(se, toPointTo: mapView),
      bottomLeft: mapView.convert(sw, toPointTo: mapView)
    )

    return Self.hitTestCorner(at: point, corners: projected, hitRadius: hitRadius)
  }

  func shouldBeginPan(
    at touchPoint: CGPoint,
    in mapView: MLNMapView,
    offlineViewModel: OfflineSelectionViewModel,
    hitRadius: CGFloat
  ) -> Bool {
    hitTestCorner(
      at: touchPoint,
      in: mapView,
      offlineViewModel: offlineViewModel,
      hitRadius: hitRadius
    ) != nil
  }

  func handlePan(
    _ sender: UIPanGestureRecognizer,
    in mapView: MLNMapView,
    offlineViewModel: OfflineSelectionViewModel,
    hitRadius: CGFloat,
    onUserInteraction: () -> Void
  ) {
    guard offlineViewModel.isSelectionModeActive else {
      if activeDraggedCorner != nil {
        styleSynchronizer.updateOfflineSelectionBounds(nil, in: mapView.style)
      }
      resetDragState()
      return
    }

    let touchPoint = sender.location(in: mapView)

    switch sender.state {
    case .began:
      guard let corner = hitTestCorner(
        at: touchPoint,
        in: mapView,
        offlineViewModel: offlineViewModel,
        hitRadius: hitRadius
      ),
      let initialBounds = offlineViewModel.selectedBounds else {
        return
      }
      activeDraggedCorner = corner
      dragInitialBounds = initialBounds
      dragCurrentBounds = initialBounds
      lastPanUpdateTime = CACurrentMediaTime()
      onUserInteraction()

    case .changed:
      guard let corner = activeDraggedCorner,
            let initialBounds = dragInitialBounds else { return }
      let now = CACurrentMediaTime()
      guard now - lastPanUpdateTime >= Self.panThrottleInterval else { return }
      lastPanUpdateTime = now

      let coord = mapView.convert(touchPoint, toCoordinateFrom: mapView)
      let updatedBounds = Self.computeUpdatedBounds(from: initialBounds, dragging: corner, to: coord)
      dragCurrentBounds = updatedBounds

      // Isolated visual update: directly mutate MapLibre vector layers to prevent SwiftUI render storm
      // while keeping `styleSynchronizer.lastSnapshot` aligned with the rendered geometry.
      styleSynchronizer.updateOfflineSelectionBounds(updatedBounds, in: mapView.style)

    case .ended:
      let committedBounds: GeographicBoundingBox?
      if let corner = activeDraggedCorner,
         let initialBounds = dragInitialBounds {
        let coord = mapView.convert(touchPoint, toCoordinateFrom: mapView)
        committedBounds = Self.computeUpdatedBounds(from: initialBounds, dragging: corner, to: coord)
      } else {
        committedBounds = dragCurrentBounds
      }
      resetDragState()
      if let finalBounds = committedBounds {
        if styleSynchronizer.lastSnapshot?.offlineSelectionBounds != finalBounds {
          styleSynchronizer.updateOfflineSelectionBounds(finalBounds, in: mapView.style)
        }
        offlineViewModel.updateBoundingBox(finalBounds)
      }

    case .cancelled, .failed:
      let restoredBounds = offlineViewModel.isSelectionModeActive ? offlineViewModel.selectedBounds : nil
      styleSynchronizer.updateOfflineSelectionBounds(restoredBounds, in: mapView.style)
      resetDragState()

    default:
      break
    }
  }

  private func resetDragState() {
    activeDraggedCorner = nil
    dragInitialBounds = nil
    dragCurrentBounds = nil
  }
}
