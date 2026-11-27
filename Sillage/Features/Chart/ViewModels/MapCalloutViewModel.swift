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
  var activeError: Error? = nil
  var targetCoordinate: CLLocationCoordinate2D? = nil
  var targetWaypointID: String? = nil
  var isCentering: Bool = false
  var aimingCoordinate: CLLocationCoordinate2D? = nil
  /// Screen-space magnetic pull offset applied to the SwiftUI reticle while panning near a waypoint.
  /// Always `.zero` when no waypoint is targeted.
  private(set) var reticleVisualOffset: CGSize = .zero
  
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

  /// Dynamic conversion instruction for the magnetic declination section footer.
  var magneticDeclinationFooterText: String? {
    magneticDeclination?.marineDeclinationConversionFooter
  }
  
  /// Starts crosshair aiming under the user's finger during a long press gesture
  /// and immediately presents the callout dialog.
  func startAimingPreview(at coordinate: CLLocationCoordinate2D, waypointID: String? = nil) {
    self.targetCoordinate = coordinate
    self.targetWaypointID = waypointID
    self.aimingCoordinate = coordinate
    self.isCentering = false
    self.reticleVisualOffset = .zero
    self.isCalloutVisible = true
    syncPointInformationForNewTarget(immediate: true)
  }

  /// Updates preview aiming location as the user drags their finger before release.
  /// Preserves existing point info to prevent skeleton flashing while aiming settles.
  func updateAimingPreview(at coordinate: CLLocationCoordinate2D, waypointID: String? = nil) {
    self.targetCoordinate = coordinate
    self.targetWaypointID = waypointID
    self.aimingCoordinate = coordinate
    self.reticleVisualOffset = .zero
    syncPointInformationForNewTarget(immediate: false)
  }

  /// Cancels preview aiming and resets aiming state.
  func cancelAimingPreview() {
    pointInfoFetchTask?.cancel()
    pointInfoFetchTask = nil
    self.aimingCoordinate = nil
    self.isCentering = false
    self.reticleVisualOffset = .zero
    self.isPointInfoPresented = false
    self.isCalloutVisible = false
    self.activeError = nil
    self.targetCoordinate = nil
    self.targetWaypointID = nil
    self.sunEphemeris = nil
    self.magneticDeclination = nil
    self.isPointInfoLoading = false
  }

  /// Begins targeting a map location (or snapped waypoint) with crosshair aiming.
  /// - Parameters:
  ///   - coordinate: Geographic coordinate touch point (or exact waypoint coordinate if snapped).
  ///   - waypointID: Optional snapped waypoint identifier.
  ///   - needsCentering: True if MapLibre must fly the camera to center this point.
  func beginAiming(
    at coordinate: CLLocationCoordinate2D,
    waypointID: String? = nil,
    needsCentering: Bool
  ) {
    self.targetCoordinate = coordinate
    self.targetWaypointID = waypointID
    self.aimingCoordinate = needsCentering ? coordinate : nil
    self.isCentering = needsCentering
    self.reticleVisualOffset = .zero
    self.isCalloutVisible = true
    syncPointInformationForNewTarget(immediate: !needsCentering)
  }

  /// Finalizes the centering flight once the camera has arrived at the screen center.
  func completeCentering(at mapCenter: CLLocationCoordinate2D, waypointID: String? = nil) {
    self.aimingCoordinate = nil
    self.isCentering = false
    self.reticleVisualOffset = .zero
    self.targetCoordinate = mapCenter
    self.targetWaypointID = waypointID
    syncPointInformationForNewTarget(immediate: true)
  }

  /// Interrupts the centering flight (e.g. user dragged the map mid-flight or window resized).
  func interruptCentering(
    at mapCenter: CLLocationCoordinate2D,
    waypointID: String? = nil,
    visualOffset: CGSize = .zero
  ) {
    self.aimingCoordinate = nil
    self.isCentering = false
    self.reticleVisualOffset = waypointID != nil ? visualOffset : .zero
    self.targetCoordinate = mapCenter
    self.targetWaypointID = waypointID
    syncPointInformationForNewTarget(immediate: false)
  }

  /// Updates target coordinate, optional magnetically snapped waypoint, and reticle visual offset during chart panning.
  /// Enforces that `reticleVisualOffset` resets to `.zero` whenever `waypointID == nil`.
  func updateTarget(
    coordinate: CLLocationCoordinate2D,
    waypointID: String? = nil,
    visualOffset: CGSize = .zero
  ) {
    self.targetCoordinate = coordinate
    self.targetWaypointID = waypointID
    self.reticleVisualOffset = waypointID != nil ? visualOffset : .zero
    syncPointInformationForNewTarget(immediate: false)
  }

  /// Updates only the screen-space magnetic visual offset at display refresh rate without retriggering point info fetches.
  func updateReticleVisualOffset(_ offset: CGSize) {
    let resolvedOffset = targetWaypointID != nil ? offset : .zero
    if self.reticleVisualOffset != resolvedOffset {
      self.reticleVisualOffset = resolvedOffset
    }
  }
  
  /// Presents the contextual point information dialog.
  func presentPointInfo(for date: Date = Date()) {
    self.isPointInfoPresented = true
    fetchPointInformation(for: date)
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
    self.activeError = nil
    self.targetWaypointID = nil
    self.aimingCoordinate = nil
    self.isCentering = false
    self.reticleVisualOffset = .zero
    self.sunEphemeris = nil
    self.magneticDeclination = nil
    self.isPointInfoLoading = false
  }

  /// Synchronizes point information state when targeting a new location.
  /// Refetches ephemeris and declination if point info is open, or resets state cleanly if closed.
  private func syncPointInformationForNewTarget(
    for date: Date = Date(),
    immediate: Bool = false
  ) {
    if isPointInfoPresented {
      fetchPointInformation(for: date, immediate: immediate)
    } else {
      pointInfoFetchTask?.cancel()
      pointInfoFetchTask = nil
      self.sunEphemeris = nil
      self.magneticDeclination = nil
      self.isPointInfoLoading = false
    }
  }

  /// Fetches astronomical ephemeris and magnetic declination in parallel for the current target coordinate.
  /// Preserves existing values during recalculation to prevent skeleton placeholder flashing.
  /// Throttles periodic updates during continuous map gestures (every 150ms) and reads the latest coordinate on wake-up.
  func fetchPointInformation(
    for date: Date = Date(),
    immediate: Bool = false
  ) {
    guard isPointInfoPresented, targetCoordinate != nil else {
      pointInfoFetchTask?.cancel()
      pointInfoFetchTask = nil
      sunEphemeris = nil
      magneticDeclination = nil
      isPointInfoLoading = false
      return
    }

    // Only display loading placeholder if no prior values exist yet (initial presentation)
    if sunEphemeris == nil && magneticDeclination == nil {
      self.isPointInfoLoading = true
      if immediate || pointInfoFetchTask == nil {
        pointInfoFetchTask?.cancel()
        pointInfoFetchTask = nil
        startPointInfoCalculationTask(date: date, delay: nil)
      }
      return
    }

    if immediate {
      pointInfoFetchTask?.cancel()
      pointInfoFetchTask = nil
      startPointInfoCalculationTask(date: date, delay: nil)
      return
    }

    // Throttled periodic update during active scrolling: if a task is already running,
    // let it complete. When it wakes up, it reads the latest targetCoordinate.
    guard pointInfoFetchTask == nil else { return }

    startPointInfoCalculationTask(date: date, delay: .milliseconds(150))
  }

  private func startPointInfoCalculationTask(date: Date, delay: Duration?) {
    pointInfoFetchTask = TaskCancellable(Task { [weak self] in
      guard let self else { return }

      if let delay {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
      }

      // Loop to guarantee catching up with any coordinate updates that arrived while calculating
      while !Task.isCancelled && self.isPointInfoPresented {
        guard let coordinate = self.targetCoordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
          break
        }

        let astroService = self.astronomicalService
        let magService = self.magneticDeclinationService

        async let ephemeris = astroService.calculateEphemeris(
          for: coordinate,
          date: date,
          timeZone: .current
        )
        async let declination = magService.calculateDeclination(for: coordinate, date: date)

        let (ephemResult, declResult) = await (ephemeris, declination)

        guard !Task.isCancelled else { break }

        self.sunEphemeris = ephemResult
        self.magneticDeclination = declResult
        self.isPointInfoLoading = false

        // Check if targetCoordinate changed during calculation (trailing edge catch-up)
        guard let latestCoordinate = self.targetCoordinate else { break }
        if latestCoordinate.latitude == coordinate.latitude &&
           latestCoordinate.longitude == coordinate.longitude {
          break
        }

        // Throttle subsequent calculations during continuous dragging to 150ms
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { break }
      }

      guard !Task.isCancelled else { return }
      self.isPointInfoLoading = false
      self.pointInfoFetchTask = nil
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
    return vessel.geodesicDistance(to: target)
  }
}
