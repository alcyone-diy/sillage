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

/// Manages the state and telemetry calculation for the floating map target callout overlay.
/// Implements a hybrid anchor mode:
/// - `fixedGeographic`: Used when long-pressing an existing waypoint. Coordinate is fixed, screen position updates with map movement.
/// - `fixedScreen`: Used when long-pressing empty map space. Screen reticle stays fixed, coordinate updates as map is panned beneath it.
/// Enforces strict Swift 6 MainActor isolation and throttles map projection updates to ~10Hz.
@Observable
@MainActor
final class MapCalloutViewModel {
  
  private enum AnchorMode {
    case fixedGeographic // Target coordinate stays constant, screenPoint follows the map
    case fixedScreen     // Screen point stays constant, targetCoordinate updates as map moves under reticle
  }
  
  var isCalloutVisible: Bool = false
  var screenPoint: CGPoint = .zero
  var targetCoordinate: CLLocationCoordinate2D? = nil
  var targetWaypointID: String? = nil
  
  private var anchorMode: AnchorMode = .fixedScreen
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
    self.anchorMode = (waypointID != nil) ? .fixedGeographic : .fixedScreen
    self.isCalloutVisible = true
  }
  
  /// Dismisses the callout overlay and cancels any pending throttled projection tasks.
  func dismiss() {
    throttleTask?.cancel()
    throttleTask = nil
    self.isCalloutVisible = false
    self.targetWaypointID = nil
  }
  
  /// Throttles screen/coordinate updates during high-frequency map region changes (60-120Hz).
  /// Executes synchronously for .fixedGeographic mode (zero lag), and throttles to ~10Hz for .fixedScreen mode.
  func throttledUpdateScreenPosition(from mapView: MLNMapView) {
    guard isCalloutVisible else { return }
    
    switch anchorMode {
    case .fixedGeographic:
      // Fixed geographic mode requires zero lag during map panning.
      // Matrix projection from CLLocationCoordinate2D to screen CGPoint is lightweight,
      // so update screenPosition synchronously at full 60/120Hz display refresh rate.
      performProjectionUpdate(from: mapView)
      
    case .fixedScreen:
      // Fixed screen mode requires heavy Great Circle navigational math re-computation.
      // Throttle coordinate updates to ~10Hz (100ms interval) to conserve CPU/battery.
      guard throttleTask == nil else { return }
      let task = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(100))
        guard let self = self, !Task.isCancelled, self.isCalloutVisible else { return }
        self.performProjectionUpdate(from: mapView)
        self.throttleTask = nil
      }
      self.throttleTask = TaskCancellable(task)
    }
  }
  
  /// Forces an immediate update of screen or geographic coordinates from the map view.
  /// Called when map region animation or gesture completes.
  func updateScreenPositionImmediately(from mapView: MLNMapView) {
    guard isCalloutVisible else { return }
    throttleTask?.cancel()
    throttleTask = nil
    performProjectionUpdate(from: mapView)
  }
  
  /// Performs projection re-calculation according to the current anchorMode.
  private func performProjectionUpdate(from mapView: MLNMapView) {
    switch anchorMode {
    case .fixedGeographic:
      guard let targetCoord = targetCoordinate else { return }
      let newPoint = mapView.convert(targetCoord, toPointTo: mapView)
      if mapView.bounds.contains(newPoint) {
        self.screenPoint = newPoint
      } else {
        self.dismiss()
      }
    case .fixedScreen:
      self.targetCoordinate = mapView.convert(self.screenPoint, toCoordinateFrom: mapView)
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
    let boatLoc = CLLocation(latitude: vessel.latitude, longitude: vessel.longitude)
    let targetLoc = CLLocation(latitude: target.latitude, longitude: target.longitude)
    let distanceInMeters = boatLoc.distance(from: targetLoc)
    guard distanceInMeters >= 0 else { return nil }
    return Measurement(value: distanceInMeters, unit: UnitLength.meters)
  }
}
