//
//  CoreLocationPositioningService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import OSLog
import os

@MainActor
public protocol BackgroundLocationToken: AnyObject {
  func invalidate()
}

/// Hardware positioning service bridging Apple CoreLocation with the Sillage positioning domain.
///
/// Architecture & Design Decisions:
/// - **Single CoreLocation Stream (`CLLocationManager`)**: Uses a single `CLLocationManager` instance
///   with `locationManager(_:didUpdateLocations:)` funneled sequentially via an `AsyncStream<[CLLocation]>`
///   to the `@MainActor`. `CLLocationUpdate.liveUpdates` was intentionally avoided because it runs an
///   independent session that ignores `distanceFilter`, `desiredAccuracy`, and `pausesLocationUpdatesAutomatically`
///   and auto-pauses when stationary—unsafe for anchor watch and slow drifting.
/// - **Dynamic Background Privileges (RAII)**: Dynamically toggles `allowsBackgroundLocationUpdates` and
///   `showsBackgroundLocationIndicator` based on active `BackgroundLocationToken` leases, while keeping
///   auto-pause disabled (`pausesLocationUpdatesAutomatically = false`) during background sessions.
/// - **Strict Boundary Sanitization**: Intercepts Apple sentinel values (`-1.0` for speed, course, and
///   accuracies) and drops transient invalid coordinates at the service boundary so they never leak into the domain.
@MainActor
class CoreLocationPositioningService: NSObject, PositioningService, CLLocationManagerDelegate {

  private let locationManager: CLLocationManager

  var currentAuthorizationStatus: CLAuthorizationStatus {
    locationManager.authorizationStatus
  }

  var currentDistanceFilter: Measurement<UnitLength> {
    Measurement(value: locationManager.distanceFilter, unit: .meters)
  }

  /// Exposed for unit testing verification of the underlying CLLocationManager configuration.
  var activityType: CLActivityType {
    locationManager.activityType
  }

  /// Exposed for unit testing verification of the underlying CLLocationManager configuration.
  var desiredAccuracy: CLLocationAccuracy {
    locationManager.desiredAccuracy
  }

  /// Exposed for unit testing verification of background privilege configuration.
  var allowsBackgroundLocationUpdates: Bool {
    locationManager.allowsBackgroundLocationUpdates
  }

  /// Exposed for unit testing verification of the system background indicator configuration.
  var showsBackgroundLocationIndicator: Bool {
    locationManager.showsBackgroundLocationIndicator
  }

  public private(set) var lastKnownLocation: NavigationFix?

  // MARK: - Configuration Constants

  private enum PositioningConfig {
    static let defaultDistanceFilter: Double = 10.0
    static let zeroDistance = Measurement<UnitLength>(value: 0.0, unit: .meters)
    static let degradedAccuracyThreshold = Measurement<UnitLength>(value: 50.0, unit: .meters)

    static func clAccuracy(for mode: GPSAccuracyMode) -> CLLocationAccuracy {
      switch mode {
      case .bestForNavigation: return kCLLocationAccuracyBestForNavigation
      case .best:              return kCLLocationAccuracyBest
      case .tenMeters:         return kCLLocationAccuracyNearestTenMeters
      case .hundredMeters:     return kCLLocationAccuracyHundredMeters
      }
    }
  }
  
  // MARK: - Multicast Streams
  
  private var locationContinuations: [UUID: AsyncStream<PositioningState>.Continuation] = [:]
  
  var locationUpdates: AsyncStream<PositioningState> {
    let (stream, continuation) = AsyncStream.makeStream(of: PositioningState.self)
    let id = UUID()
    locationContinuations[id] = continuation
    
    // Swift 6: onTermination is executed in a nonisolated context.
    // We must capture [weak self] in a @Sendable closure and explicitly hop back
    // to the @MainActor to safely mutate the dictionary and prevent isolation violations.
    continuation.onTermination = { @Sendable [weak self] _ in
      guard let service = self else { return }
      Task { @MainActor in
        service.locationContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }
  
  private var authContinuations: [UUID: AsyncStream<CLAuthorizationStatus>.Continuation] = [:]
  
  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> {
    let (stream, continuation) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)
    let id = UUID()
    authContinuations[id] = continuation
    
    continuation.onTermination = { @Sendable [weak self] _ in
      guard let service = self else { return }
      Task { @MainActor in
        service.authContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }
  
  private let rawLocationContinuation: AsyncStream<[CLLocation]>.Continuation
  // Guarded by an unfair lock rather than @MainActor isolation so nonisolated deinit can cancel deterministically.
  private let funnelTaskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
  private var isUpdatingLocations = false
  private var requestedFilters: [String: Double] = [:]

  // MARK: - Pauses Location Updates Automatically (Debug)

  /// Mirrors the configured debug preference independently from `locationManager.pausesLocationUpdatesAutomatically`,
  /// which is forced to `false` during active background sessions and may be coerced by CoreLocation on Simulator.
  private(set) var pausesLocationUpdatesAutomatically: Bool

  init(
    initialAccuracyMode: GPSAccuracyMode,
    initialPausesLocationUpdatesAutomatically: Bool = false
  ) {
    let (stream, continuation) = AsyncStream.makeStream(of: [CLLocation].self)
    self.rawLocationContinuation = continuation
    self.pausesLocationUpdatesAutomatically = initialPausesLocationUpdatesAutomatically
    self.locationManager = CLLocationManager()
    super.init()

    // Capture [weak self] per iteration rather than before the loop so the infinite AsyncStream
    // never retains self across suspension points and deinit remains deterministic.
    let funnelTask = Task { @MainActor [weak self] in
      for await locations in stream {
        guard !Task.isCancelled, let self = self else { break }
        for location in locations {
          self.processLocation(location)
        }
      }
    }
    self.funnelTaskLock.withLock { $0 = funnelTask }

    // Delegate handles location updates, authorization changes, and hardware errors.
    self.locationManager.delegate = self

    // Hardware Accuracy: Configured at the locationManager level so locationd applies it upstream.
    self.locationManager.desiredAccuracy = PositioningConfig.clAccuracy(for: initialAccuracyMode)
    Logger.telemetry.info("CoreLocationPositioningService initialised with accuracy: \(initialAccuracyMode.displayName, privacy: .public)")

    // Hardware Throttling: Managed in meters by locationd to prevent unnecessary CPU wakeups (Rule 10).
    self.locationManager.distanceFilter = PositioningConfig.defaultDistanceFilter

    // Marine Activity Type: Configures locationd with native marine Kalman filtering and
    // prevents coastal road snapping on iOS 27+ (.maritime), falling back to .otherNavigation on earlier iOS versions.
    if #available(iOS 27.0, *) {
      self.locationManager.activityType = .maritime
    } else {
      self.locationManager.activityType = .otherNavigation
    }

    // Marine Safety & Background Privileges: Auto-pause defaults to false; background privileges
    // and indicator are dynamically acquired via BackgroundLocationToken (Rule 10).
    self.locationManager.pausesLocationUpdatesAutomatically = initialPausesLocationUpdatesAutomatically
    self.locationManager.allowsBackgroundLocationUpdates = false
    self.locationManager.showsBackgroundLocationIndicator = false
  }

  deinit {
    // Finish the stream and cancel the funnel task deterministically; `locationManager.delegate` is weak
    // and `@MainActor`-isolated, so it is safely ignored during `nonisolated deinit`.
    rawLocationContinuation.finish()
    let task = funnelTaskLock.withLock { current -> Task<Void, Never>? in
      let existing = current
      current = nil
      return existing
    }
    task?.cancel()
  }

  // MARK: - Desired Accuracy (Debug)

  /// Applies the given accuracy mode to the underlying CLLocationManager at runtime.
  /// Must be called exclusively through AppEnvironment.updateGPSAccuracy(to:).
  func setDesiredAccuracy(_ mode: GPSAccuracyMode) {
    let accuracy = PositioningConfig.clAccuracy(for: mode)
    locationManager.desiredAccuracy = accuracy
    Logger.telemetry.info("GPS desiredAccuracy changed to \(mode.displayName, privacy: .public) (\(accuracy, privacy: .public))")
  }

  // MARK: - Pauses Location Updates Automatically (Debug)

  /// Configures pausesLocationUpdatesAutomatically on the underlying CLLocationManager at runtime.
  /// Must be called exclusively through AppEnvironment.updatePausesLocationUpdatesAutomatically(to:).
  func setPausesLocationUpdatesAutomatically(_ pauses: Bool) {
    self.pausesLocationUpdatesAutomatically = pauses
    // Never re-enable auto-pause while a background session (track/anchor) is holding privileges.
    if activeBackgroundSessions.isEmpty {
      locationManager.pausesLocationUpdatesAutomatically = pauses
    }
    Logger.telemetry.info("GPS pausesLocationUpdatesAutomatically changed to \(pauses, privacy: .public)")
  }
  
  // MARK: - Token Lifecycle

  /// RAII lease token shared by foreground update and background activity callers.
  /// `invalidate()` runs synchronously on `@MainActor` so privilege release takes effect
  /// immediately, while `deinit` provides a single-shot fallback if the caller forgets to invalidate.
  @MainActor
  private final class ManagedLocationToken: LocationUpdateToken, BackgroundLocationToken {
    private let id: UUID
    private let onInvalidate: @MainActor @Sendable (UUID) -> Void
    private let invalidatedLock = OSAllocatedUnfairLock(initialState: false)

    init(id: UUID, onInvalidate: @escaping @MainActor @Sendable (UUID) -> Void) {
      self.id = id
      self.onInvalidate = onInvalidate
    }

    func invalidate() {
      let shouldInvalidate = invalidatedLock.withLock { isInvalidated -> Bool in
        guard !isInvalidated else { return false }
        isInvalidated = true
        return true
      }
      guard shouldInvalidate else { return }
      onInvalidate(id)
    }

    // Swift 6: deinit on an actor-isolated class is always nonisolated.
    // The lock ensures deterministic single-shot cleanup across invalidate() and deinit.
    nonisolated deinit {
      let shouldInvalidate = invalidatedLock.withLock { isInvalidated -> Bool in
        guard !isInvalidated else { return false }
        isInvalidated = true
        return true
      }
      guard shouldInvalidate else { return }
      let id = self.id
      let callback = self.onInvalidate
      Task { @MainActor in
        callback(id)
      }
    }
  }

  // MARK: - Foreground Update Tracking

  private var activeUpdateTokens = Set<UUID>()

  func requestLocationUpdates() -> any LocationUpdateToken {
    let tokenID = UUID()
    let token = ManagedLocationToken(id: tokenID) { [weak self] id in
      self?.releaseUpdateToken(id: id)
    }

    let wasEmpty = activeUpdateTokens.isEmpty
    activeUpdateTokens.insert(tokenID)

    let status = locationManager.authorizationStatus
    if wasEmpty && (status == .authorizedWhenInUse || status == .authorizedAlways) {
      startUpdatingLocation()
    }

    return token
  }

  private func releaseUpdateToken(id: UUID) {
    activeUpdateTokens.remove(id)
    if activeUpdateTokens.isEmpty {
      stopUpdatingLocation()
    }
  }

  // MARK: - Background Activity Tracking

  private var activeBackgroundSessions = Set<UUID>()

  func requestBackgroundLocation() -> any BackgroundLocationToken {
    let tokenID = UUID()
    let token = ManagedLocationToken(id: tokenID) { [weak self] id in
      self?.releaseBackgroundToken(id: id)
    }

    activeBackgroundSessions.insert(tokenID)
    updateBackgroundLocationStatus()

    return token
  }
  
  private func releaseBackgroundToken(id: UUID) {
    activeBackgroundSessions.remove(id)
    updateBackgroundLocationStatus()
  }
  
  private func updateBackgroundLocationStatus() {
    let needsBackground = !activeBackgroundSessions.isEmpty
    // CLLocationManager requires both flags (with `location` in UIBackgroundModes) so background
    // tracking continues and the system indicator remains visible across WhenInUse and Always grants.
    locationManager.allowsBackgroundLocationUpdates = needsBackground
    locationManager.showsBackgroundLocationIndicator = needsBackground
    locationManager.pausesLocationUpdatesAutomatically = needsBackground ? false : pausesLocationUpdatesAutomatically
  }
  
  func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {
    let meters = distance.converted(to: .meters).value
    guard distance > PositioningConfig.zeroDistance, meters.isFinite else {
      Logger.telemetry.warning("Invalid distance filter requested by \(identifier, privacy: .public): \(meters, privacy: .public)m. Must be > 0.")
      return
    }
    requestedFilters[identifier] = meters
    recalculateDistanceFilter()
  }
  
  func removeDistanceFilter(for identifier: String) {
    requestedFilters.removeValue(forKey: identifier)
    recalculateDistanceFilter()
  }
  
  private func recalculateDistanceFilter() {
    let fallbackFilter = PositioningConfig.defaultDistanceFilter
    
    var minFilter = fallbackFilter
    var commandingService = "Default (Standby)"
    
    if let minEntry = requestedFilters.min(by: { $0.value < $1.value }) {
      minFilter = minEntry.value
      commandingService = minEntry.key
    }
    
    if locationManager.distanceFilter != minFilter {
      locationManager.distanceFilter = minFilter
      Logger.telemetry.info("Distance filter updated to \(minFilter, privacy: .public)m by \(commandingService, privacy: .public).")
    }
  }
  
  func requestAuthorization() {
    // Explicit imperative call required to trigger the initial system dialog for notDetermined state.
    locationManager.requestWhenInUseAuthorization()
  }
  
  private func startUpdatingLocation() {
    guard !isUpdatingLocations else { return }
    isUpdatingLocations = true
    Logger.telemetry.info("Starting CLLocationManager location updates")
    locationManager.startUpdatingLocation()
  }
  
  private func stopUpdatingLocation() {
    guard isUpdatingLocations else { return }
    isUpdatingLocations = false
    Logger.telemetry.info("Stopping CLLocationManager location updates")
    locationManager.stopUpdatingLocation()
  }

  private func yieldLocationState(_ state: PositioningState) {
    for continuation in locationContinuations.values {
      continuation.yield(state)
    }
  }
  
  /// Sanitizes a raw `CLLocation` at the infrastructure boundary and emits `.active` or `.degraded`
  /// states to domain subscribers, dropping isolated invalid fixes. Internal for deterministic unit testing.
  func processLocation(_ latestLocation: CLLocation) {
    let accuracy = latestLocation.horizontalAccuracy

    // 1. Drop transient invalid fixes (invalid coordinate, non-finite or negative accuracy) without
    // emitting `.lost`. Stream loss is reported via `didFailWithError` so isolated invalid samples do not
    // trigger false anchor alarms or split track segments; `lastKnownLocation` remains untouched.
    guard CLLocationCoordinate2DIsValid(latestLocation.coordinate),
          accuracy.isFinite,
          accuracy >= 0 else {
      Logger.telemetry.warning("CoreLocationPositioningService dropped invalid fix (accuracy: \(accuracy, privacy: .public)m)")
      return
    }
    
    // Wrap once in Measurement and compare directly against the precomputed threshold to avoid unit conversion overhead (Rule 4).
    let horizontalAccuracy = Measurement<UnitLength>(value: accuracy, unit: .meters)

    // 2. Mark as degraded if accuracy is poor, but coordinate is physically valid
    let isDegraded = horizontalAccuracy > PositioningConfig.degradedAccuracyThreshold
    
    if isDegraded {
      Logger.telemetry.warning("CoreLocationPositioningService coordinates are degraded: \(accuracy, privacy: .public)m")
    }
    
    // 3. Couple course & courseAccuracy: CoreLocation uses -1.0 independently on either field when invalid,
    // and NavigationFix requires both or neither. Normalize 360° -> 0° to satisfy the SQLite `< 360` CHECK constraint.
    let rawCourse = latestLocation.course
    let rawCourseAccuracy = latestLocation.courseAccuracy
    var courseOverGround: Measurement<UnitAngle>?
    var courseOverGroundAccuracy: Measurement<UnitAngle>?
    if rawCourse.isFinite, rawCourseAccuracy.isFinite,
       rawCourse >= 0, rawCourse <= 360, rawCourseAccuracy >= 0 {
      let normalizedCourse = rawCourse == 360 ? 0 : rawCourse
      courseOverGround = Measurement(value: normalizedCourse, unit: .degrees)
      courseOverGroundAccuracy = Measurement(value: rawCourseAccuracy, unit: .degrees)
    }
    
    // 4. Couple speed & speedAccuracy: speed must also be checked >= 0 because speedAccuracy >= 0 does not
    // guarantee a valid speed, and leaking -1.0 breaks HUD/anchor displays and SQLite `>= 0` CHECK constraints.
    let rawSpeed = latestLocation.speed
    let rawSpeedAccuracy = latestLocation.speedAccuracy
    var speedOverGround: Measurement<UnitSpeed>?
    var speedOverGroundAccuracy: Measurement<UnitSpeed>?
    if rawSpeed.isFinite, rawSpeedAccuracy.isFinite,
       rawSpeed >= 0, rawSpeedAccuracy >= 0 {
      speedOverGround = Measurement(value: rawSpeed, unit: .metersPerSecond)
      speedOverGroundAccuracy = Measurement(value: rawSpeedAccuracy, unit: .metersPerSecond)
    }
    
    let filteredLocation = NavigationFix(
      coordinate: latestLocation.coordinate,
      horizontalAccuracy: horizontalAccuracy,
      courseOverGround: courseOverGround,
      courseOverGroundAccuracy: courseOverGroundAccuracy,
      speedOverGround: speedOverGround,
      speedOverGroundAccuracy: speedOverGroundAccuracy,
      timestamp: latestLocation.timestamp
    )
    
    self.lastKnownLocation = filteredLocation
    
    let state: PositioningState = isDegraded ? .degraded(filteredLocation) : .active(filteredLocation)
    yieldLocationState(state)
  }

  // MARK: - CLLocationManagerDelegate

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    // Funnel through an AsyncStream to guarantee sequential, deterministic processing on the MainActor.
    rawLocationContinuation.yield(locations)
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    // Snapshot status synchronously before hopping actors so we observe the callback's exact state.
    let status = manager.authorizationStatus
    Task { @MainActor [weak self] in
      guard let self = self else { return }
      for continuation in self.authContinuations.values {
        continuation.yield(status)
      }
      
      switch status {
      case .authorizedWhenInUse, .authorizedAlways:
        if !self.activeUpdateTokens.isEmpty {
          self.startUpdatingLocation()
        }
      default:
        self.stopUpdatingLocation()
      }
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Logger.telemetry.error("CoreLocationPositioningService failed with error: \(error.localizedDescription, privacy: .public)")
    Task { @MainActor [weak self] in
      guard let self = self else { return }
      self.yieldLocationState(.lost(error))
    }
  }
}
