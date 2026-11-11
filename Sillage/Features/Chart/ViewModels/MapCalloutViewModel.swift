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
  var isPointInfoPresented: Bool = false
  var targetCoordinate: CLLocationCoordinate2D? = nil
  var targetWaypointID: String? = nil
  var isCentering: Bool = false
  var aimingCoordinate: CLLocationCoordinate2D? = nil
  private(set) var lastSheetHeight: CGFloat = 220
  
  // MARK: - Point Information (Ephemeris & Magnetism)
  
  var sunEphemeris: SunEphemeris? = nil
  var magneticDeclination: Measurement<UnitAngle>? = nil
  var isPointInfoLoading: Bool = false
  
  private let astronomicalService: AstronomicalService
  private let magneticDeclinationService: MagneticDeclinationService
  private var pointInfoFetchTask: TaskCancellable? = nil

  init(
    astronomicalService: AstronomicalService = AstronomicalService(),
    magneticDeclinationService: MagneticDeclinationService = MagneticDeclinationService()
  ) {
    self.astronomicalService = astronomicalService
    self.magneticDeclinationService = magneticDeclinationService
  }

  /// Formatted coordinate string for UI presentation without altering raw coordinate precision.
  var formattedCoordinate: String? {
    targetCoordinate?.formatted(.marineCoordinate)
  }
  
  /// Closure invoked when the UI requests ensuring the target point is not obscured by overlay sheets.
  var onEnsureVisibleRequested: (@MainActor (CGFloat) -> Void)? = nil
  
  /// Presents the map callout overlay for an existing waypoint.
  func presentWaypointCallout(coordinate: CLLocationCoordinate2D, waypointID: String) {
    pointInfoFetchTask?.cancel()
    pointInfoFetchTask = nil
    self.targetCoordinate = coordinate
    self.targetWaypointID = waypointID
    self.aimingCoordinate = nil
    self.isCentering = false
    self.isPointInfoPresented = false
    self.sunEphemeris = nil
    self.magneticDeclination = nil
    self.isPointInfoLoading = false
    self.isCalloutVisible = true
  }

  /// Starts crosshair aiming under the user's finger during a long press gesture
  /// and immediately presents the callout dialog.
  func startAimingPreview(at coordinate: CLLocationCoordinate2D) {
    pointInfoFetchTask?.cancel()
    pointInfoFetchTask = nil
    self.targetCoordinate = coordinate
    self.targetWaypointID = nil
    self.aimingCoordinate = coordinate
    self.isCentering = false
    self.isPointInfoPresented = false
    self.sunEphemeris = nil
    self.magneticDeclination = nil
    self.isPointInfoLoading = false
    self.isCalloutVisible = true
  }

  /// Updates preview aiming location as the user drags their finger before release.
  func updateAimingPreview(at coordinate: CLLocationCoordinate2D) {
    self.targetCoordinate = coordinate
    self.aimingCoordinate = coordinate
    if isPointInfoPresented {
      fetchPointInformation()
    }
  }

  /// Cancels preview aiming and resets aiming state.
  func cancelAimingPreview() {
    pointInfoFetchTask?.cancel()
    pointInfoFetchTask = nil
    self.aimingCoordinate = nil
    self.isCentering = false
    self.isPointInfoPresented = false
    self.isCalloutVisible = false
    self.targetCoordinate = nil
    self.sunEphemeris = nil
    self.magneticDeclination = nil
    self.isPointInfoLoading = false
  }

  /// Begins targeting an empty map location with crosshair aiming.
  /// - Parameters:
  ///   - coordinate: Geographic coordinate touch point.
  ///   - needsCentering: True if MapLibre must fly the camera to center this point.
  func beginAiming(at coordinate: CLLocationCoordinate2D, needsCentering: Bool) {
    pointInfoFetchTask?.cancel()
    pointInfoFetchTask = nil
    self.targetCoordinate = coordinate
    self.targetWaypointID = nil
    self.aimingCoordinate = needsCentering ? coordinate : nil
    self.isCentering = needsCentering
    self.isPointInfoPresented = false
    self.sunEphemeris = nil
    self.magneticDeclination = nil
    self.isPointInfoLoading = false
    self.isCalloutVisible = true
  }

  /// Finalizes the centering flight once the camera has arrived at the screen center.
  func completeCentering(at mapCenter: CLLocationCoordinate2D) {
    self.aimingCoordinate = nil
    self.isCentering = false
    self.targetCoordinate = mapCenter
    if isPointInfoPresented {
      fetchPointInformation()
    }
  }

  /// Interrupts the centering flight (e.g. user dragged the map mid-flight or window resized).
  func interruptCentering(at mapCenter: CLLocationCoordinate2D) {
    self.aimingCoordinate = nil
    self.isCentering = false
    self.targetCoordinate = mapCenter
    if isPointInfoPresented {
      fetchPointInformation()
    }
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
    if isPointInfoPresented {
      fetchPointInformation()
    }
  }
  
  /// Requests the map view to pan upwards if the target point is obscured by the bottom sheet.
  /// - Parameter sheetHeight: The rendered height of the bottom sheet.
  func ensureVisible(sheetHeight: CGFloat) {
    self.lastSheetHeight = sheetHeight
    guard isCalloutVisible else { return }
    onEnsureVisibleRequested?(sheetHeight)
  }
  
  /// Presents the contextual point information dialog.
  func presentPointInfo() {
    self.isPointInfoPresented = true
    fetchPointInformation()
  }

  /// Dismisses the contextual point information dialog.
  func dismissPointInfo() {
    pointInfoFetchTask?.cancel()
    pointInfoFetchTask = nil
    self.isPointInfoPresented = false
    self.isPointInfoLoading = false
    self.sunEphemeris = nil
    self.magneticDeclination = nil
  }

  /// Dismisses the callout overlay and its associated dialogs.
  func dismiss() {
    pointInfoFetchTask?.cancel()
    pointInfoFetchTask = nil
    self.isCalloutVisible = false
    self.isPointInfoPresented = false
    self.targetWaypointID = nil
    self.aimingCoordinate = nil
    self.isCentering = false
    self.sunEphemeris = nil
    self.magneticDeclination = nil
    self.isPointInfoLoading = false
  }

  /// Fetches astronomical ephemeris and magnetic declination in parallel for the current target coordinate.
  /// Launches a structured task calling both actor services asynchronously.
  func fetchPointInformation(for date: Date = Date()) {
    pointInfoFetchTask?.cancel()
    
    guard isPointInfoPresented, let coordinate = targetCoordinate else {
      sunEphemeris = nil
      magneticDeclination = nil
      isPointInfoLoading = false
      return
    }

    isPointInfoLoading = true

    pointInfoFetchTask = TaskCancellable(Task { [weak self] in
      guard let self else { return }
      let astroService = self.astronomicalService
      let magService = self.magneticDeclinationService

      async let ephemeris = astroService.calculateEphemeris(for: coordinate, date: date)
      async let declination = magService.calculateDeclination(for: coordinate, date: date)

      let (ephemResult, declResult) = await (ephemeris, declination)

      guard !Task.isCancelled else { return }
      self.sunEphemeris = ephemResult
      self.magneticDeclination = declResult
      self.isPointInfoLoading = false
    })
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
