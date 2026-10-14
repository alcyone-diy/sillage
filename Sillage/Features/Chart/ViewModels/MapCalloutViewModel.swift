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
  var crosshairOffset: CGSize = .zero
  var isCentering: Bool = false
  private(set) var lastSheetHeight: CGFloat = 220
  
  /// Formatted coordinate string for UI presentation without altering raw coordinate precision.
  var formattedCoordinate: String? {
    targetCoordinate?.formatted(.marineCoordinate)
  }
  
  /// Closure invoked when the UI requests ensuring the target point is not obscured by overlay sheets.
  var onEnsureVisibleRequested: (@MainActor (CGFloat) -> Void)? = nil
  
  /// Presents the map callout overlay at the specified geographic coordinate.
  /// - Parameters:
  ///   - coordinate: Geographic coordinate under the target.
  ///   - waypointID: Optional ID if an existing waypoint feature was selected.
  ///   - initialOffset: Optional screen offset from the center of the viewport for animated centering.
  func presentCallout(
    coordinate: CLLocationCoordinate2D,
    waypointID: String? = nil,
    initialOffset: CGSize = .zero
  ) {
    self.targetCoordinate = coordinate
    self.targetWaypointID = waypointID
    self.crosshairOffset = initialOffset
    self.isCentering = (initialOffset != .zero)
    self.isCalloutVisible = true
  }

  /// Centers the crosshair at the mathematical center of the map viewport.
  func centerCrosshair() {
    self.crosshairOffset = .zero
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
    self.crosshairOffset = .zero
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
