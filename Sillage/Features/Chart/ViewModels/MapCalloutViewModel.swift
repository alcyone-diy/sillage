//
//  MapCalloutViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation
import MapLibre

/// Manages the state and telemetry calculation for the map target callout overlay.
/// Geographic coordinate is fixed, and screen position updates synchronously with map movement (zero lag).
/// Enforces strict Swift 6 MainActor isolation.
@Observable
@MainActor
final class MapCalloutViewModel {
  
  var isCalloutVisible: Bool = false
  var screenPoint: CGPoint = .zero
  var targetCoordinate: CLLocationCoordinate2D? = nil
  var targetWaypointID: String? = nil
  
  /// Formatted coordinate string for UI presentation without altering raw coordinate precision.
  var formattedCoordinate: String? {
    targetCoordinate?.formatted(.marineCoordinate)
  }
  
  /// Closure invoked when the UI requests ensuring the target point is not obscured by overlay sheets.
  var onEnsureVisibleRequested: (@MainActor (CGFloat) -> Void)? = nil
  
  private var throttleTask: TaskCancellable?
  
  /// Presents the map callout overlay at the specified screen point and coordinate.
  /// - Parameters:
  ///   - point: Initial touch point on screen in local view coordinates.
  ///   - coordinate: Geographic coordinate under the touch point.
  ///   - waypointID: Optional ID if an existing waypoint feature was long-pressed.
  func presentCallout(at point: CGPoint, coordinate: CLLocationCoordinate2D, waypointID: String? = nil) {
    self.screenPoint = point
    self.targetCoordinate = coordinate
    self.targetWaypointID = waypointID
    self.isCalloutVisible = true
  }
  
  /// Requests the map view to pan upwards if the target point is obscured by the bottom sheet.
  /// - Parameter sheetHeight: The rendered height of the bottom sheet.
  func ensureVisible(sheetHeight: CGFloat) {
    guard isCalloutVisible else { return }
    onEnsureVisibleRequested?(sheetHeight)
  }
  
  /// Dismisses the callout overlay and cancels any pending throttled projection tasks.
  func dismiss() {
    throttleTask?.cancel()
    throttleTask = nil
    self.isCalloutVisible = false
    self.targetWaypointID = nil
  }
  
  /// Throttles screen position updates during high-frequency map region changes (60-120Hz).
  /// Matrix projection from CLLocationCoordinate2D to screen CGPoint is lightweight,
  /// so screenPosition is updated synchronously at full 60/120Hz display refresh rate with zero lag.
  func throttledUpdateScreenPosition(from mapView: MLNMapView) {
    guard isCalloutVisible else { return }
    performProjectionUpdate(from: mapView)
  }
  
  /// Forces an immediate update of screen coordinates from the map view.
  /// Called when map region animation or gesture completes.
  func updateScreenPositionImmediately(from mapView: MLNMapView) {
    guard isCalloutVisible else { return }
    throttleTask?.cancel()
    throttleTask = nil
    performProjectionUpdate(from: mapView)
  }
  
  private static let screenPointUpdateThreshold: CGFloat = 0.5
  
  /// Performs projection re-calculation from target geographic coordinate to screen point.
  private func performProjectionUpdate(from mapView: MLNMapView) {
    guard let targetCoord = targetCoordinate else { return }
    let newPoint = mapView.convert(targetCoord, toPointTo: mapView)
    if mapView.bounds.contains(newPoint) {
      if abs(self.screenPoint.x - newPoint.x) >= Self.screenPointUpdateThreshold ||
         abs(self.screenPoint.y - newPoint.y) >= Self.screenPointUpdateThreshold {
        self.screenPoint = newPoint
      }
    } else {
      self.dismiss()
    }
  }
  
  /// Calculates the Great Circle initial bearing from the vessel to the target coordinate.
  /// - Parameter vesselCoordinate: The current coordinate of the vessel.
  /// - Returns: Compass bearing as a `Measurement<UnitAngle>`, or `nil` if telemetry is incomplete.
  func bearing(from vesselCoordinate: CLLocationCoordinate2D?) -> Measurement<UnitAngle>? {
    guard let vessel = vesselCoordinate, let target = targetCoordinate else { return nil }
    return vessel.greatCircleBearing(to: target)
  }
  
  /// Calculates the physical distance from the vessel to the target coordinate.
  /// - Parameter vesselCoordinate: The current coordinate of the vessel.
  /// - Returns: Physical distance as a `Measurement<UnitLength>`, or `nil` if telemetry is incomplete.
  func distance(from vesselCoordinate: CLLocationCoordinate2D?) -> Measurement<UnitLength>? {
    guard let vessel = vesselCoordinate, let target = targetCoordinate else { return nil }
    return vessel.distance(to: target)
  }
}
