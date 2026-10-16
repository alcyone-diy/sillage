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

/// Manages the state and telemetry calculation for the map target callout overlay.
/// Geographic coordinate is fixed or dragged, with native MapLibre GPU pin rendering.
/// Enforces strict Swift 6 MainActor isolation.
@Observable
@MainActor
final class MapCalloutViewModel {
  
  var isCalloutVisible: Bool = false
  var targetCoordinate: CLLocationCoordinate2D? = nil
  var targetWaypointID: String? = nil
  var isCentering: Bool = false
  var aimingCoordinate: CLLocationCoordinate2D? = nil
  private(set) var lastSheetHeight: CGFloat = 220
  
  /// Formatted coordinate string for UI presentation without altering raw coordinate precision.
  var formattedCoordinate: String? {
    targetCoordinate?.formatted(.marineCoordinate)
  }
  
  /// Closure invoked when the UI requests ensuring the target point is not obscured by overlay sheets.
  var onEnsureVisibleRequested: (@MainActor (CGFloat) -> Void)? = nil
  
  /// Presents the map callout overlay for an existing waypoint.
  func presentWaypointCallout(coordinate: CLLocationCoordinate2D, waypointID: String) {
    self.targetCoordinate = coordinate
    self.targetWaypointID = waypointID
    self.aimingCoordinate = nil
    self.isCentering = false
    self.isCalloutVisible = true
  }

  /// Starts crosshair aiming under the user's finger during a long press gesture
  /// and immediately presents the callout dialog.
  func startAimingPreview(at coordinate: CLLocationCoordinate2D) {
    self.targetCoordinate = coordinate
    self.targetWaypointID = nil
    self.aimingCoordinate = coordinate
    self.isCentering = false
    self.isCalloutVisible = true
  }

  /// Updates preview aiming location as the user drags their finger before release.
  func updateAimingPreview(at coordinate: CLLocationCoordinate2D) {
    self.targetCoordinate = coordinate
    self.aimingCoordinate = coordinate
  }

  /// Cancels preview aiming and resets aiming state.
  func cancelAimingPreview() {
    self.aimingCoordinate = nil
    self.isCentering = false
    self.isCalloutVisible = false
    self.targetCoordinate = nil
  }

  /// Begins targeting an empty map location with crosshair aiming.
  /// - Parameters:
  ///   - coordinate: Geographic coordinate touch point.
  ///   - needsCentering: True if MapLibre must fly the camera to center this point.
  func beginAiming(at coordinate: CLLocationCoordinate2D, needsCentering: Bool) {
    self.targetCoordinate = coordinate
    self.targetWaypointID = nil
    self.aimingCoordinate = needsCentering ? coordinate : nil
    self.isCentering = needsCentering
    self.isCalloutVisible = true
  }

  /// Finalizes the centering flight once the camera has arrived at the screen center.
  func completeCentering(at mapCenter: CLLocationCoordinate2D) {
    self.aimingCoordinate = nil
    self.isCentering = false
    self.targetCoordinate = mapCenter
  }

  /// Interrupts the centering flight (e.g. user dragged the map mid-flight or window resized).
  func interruptCentering(at mapCenter: CLLocationCoordinate2D) {
    self.aimingCoordinate = nil
    self.isCentering = false
    self.targetCoordinate = mapCenter
  }

  /// Presents the map callout overlay at the specified geographic coordinate.
  func presentCallout(
    coordinate: CLLocationCoordinate2D,
    waypointID: String? = nil,
    needsCentering: Bool = false
  ) {
    if let waypointID {
      presentWaypointCallout(coordinate: coordinate, waypointID: waypointID)
    } else {
      beginAiming(at: coordinate, needsCentering: needsCentering)
    }
  }
  
  /// Updates target coordinate during chart panning.
  func updateTarget(coordinate: CLLocationCoordinate2D) {
    self.targetCoordinate = coordinate
  }
  
  /// Requests the map view to pan upwards if the target point is obscured by the bottom sheet.
  /// - Parameter sheetHeight: The rendered height of the bottom sheet.
  func ensureVisible(sheetHeight: CGFloat) {
    self.lastSheetHeight = sheetHeight
    guard isCalloutVisible else { return }
    onEnsureVisibleRequested?(sheetHeight)
  }
  
  /// Dismisses the callout overlay.
  func dismiss() {
    self.isCalloutVisible = false
    self.targetWaypointID = nil
    self.aimingCoordinate = nil
    self.isCentering = false
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
