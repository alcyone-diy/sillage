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

@MainActor
public protocol BackgroundLocationToken: AnyObject {
  func invalidate()
}

/// Hardware positioning service bridging Apple CoreLocation with the Sillage positioning domain.
///
/// Architecture & Design Decisions:
/// - **Modern Swift Concurrency (`CLLocationUpdate.liveUpdates`)**: Receives location fixes through a
///   native `AsyncSequence` configured with `.otherNavigation`, decoupling ingestion from legacy delegate buffers.
/// - **Hardware-Level Power & Throttling (`CLLocationManager`)**: Keeps an internal `CLLocationManager`
///   instance exclusively to configure underlying hardware filters (`distanceFilter`, `desiredAccuracy`).
///   This ensures `locationd` throttles updates in hardware rather than waking the CPU at 1 Hz.
/// - **System Authorization Lifecycle**: Conforms to `NSObject` and `CLLocationManagerDelegate`
///   specifically to intercept `locationManagerDidChangeAuthorization` and bridge status changes to `authContinuations`.
/// - **Marine Safety**: Unconditionally disables `pausesLocationUpdatesAutomatically` to ensure GPS fixes
///   never cease while drifting, sailing slowly, or standing an anchor watch.
@MainActor
class CoreLocationPositioningService: NSObject, PositioningService, CLLocationManagerDelegate {
  
  private let locationManager: CLLocationManager
  
  var currentAuthorizationStatus: CLAuthorizationStatus {
    locationManager.authorizationStatus
  }
  
  var currentDistanceFilter: Measurement<UnitLength> {
    Measurement(value: locationManager.distanceFilter, unit: .meters)
  }
  
  public private(set) var lastKnownLocation: NavigationFix?
  
  // MARK: - Configuration Constants
  
  private enum PositioningConfig {
    static let defaultDistanceFilter: Double = 10.0

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
  
  private var updateTask: Task<Void, Never>?
  private var serviceSession: CLServiceSession?
  private var requestedFilters: [String: Double] = [:]

  init(initialAccuracyMode: GPSAccuracyMode) {
    self.locationManager = CLLocationManager()
    super.init()

    // Delegate is retained strictly for authorization and hardware error callbacks.
    self.locationManager.delegate = self

    // Hardware Accuracy: Configured at the locationManager level so locationd applies it upstream.
    self.locationManager.desiredAccuracy = PositioningConfig.clAccuracy(for: initialAccuracyMode)
    Logger.telemetry.info("CoreLocationPositioningService initialised with accuracy: \(initialAccuracyMode.displayName, privacy: .public)")
    
    // Hardware Throttling: Managed in meters by locationd to prevent unnecessary CPU wakeups (Rule 10).
    self.locationManager.distanceFilter = PositioningConfig.defaultDistanceFilter

    // Marine Activity Type: Informs locationd of marine navigation, preventing coastal road snapping.
    self.locationManager.activityType = .otherNavigation

    // Marine Safety: A vessel is never paused. Unconditionally set to false to prevent
    // iOS from silently suspending GPS updates during slow drifting or anchor watch.
    self.locationManager.pausesLocationUpdatesAutomatically = false
  }

  deinit {
    updateTask?.cancel()
    backgroundActivitySession?.invalidate()
    serviceSession?.invalidate()
  }

  // MARK: - Desired Accuracy (Debug)

  /// Applies the given accuracy mode to the underlying CLLocationManager at runtime.
  /// Must be called exclusively through AppEnvironment.updateGPSAccuracy(to:).
  func setDesiredAccuracy(_ mode: GPSAccuracyMode) {
    let accuracy = PositioningConfig.clAccuracy(for: mode)
    locationManager.desiredAccuracy = accuracy
    Logger.telemetry.info("GPS desiredAccuracy changed to \(mode.displayName, privacy: .public) (\(accuracy, privacy: .public))")
  }
  
  // MARK: - Foreground Update Tracking
  
  private var activeUpdateTokens = Set<UUID>()
  
  @MainActor
  private final class LocationUpdateTokenImpl: LocationUpdateToken {
    let id: UUID
    private let onDeinit: @Sendable (UUID) -> Void
    private var isInvalidated = false
    
    init(id: UUID, onDeinit: @escaping @Sendable (UUID) -> Void) {
      self.id = id
      self.onDeinit = onDeinit
    }
    
    func invalidate() {
      guard !isInvalidated else { return }
      isInvalidated = true
      onDeinit(id)
    }
    
    nonisolated deinit {
      onDeinit(id)
    }
  }
  
  func requestLocationUpdates() -> any LocationUpdateToken {
    let tokenID = UUID()
    let token = LocationUpdateTokenImpl(id: tokenID) { @Sendable [weak self] id in
      guard let service = self else { return }
      Task { @MainActor in
        service.releaseUpdateToken(id: id)
      }
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
  private var backgroundActivitySession: CLBackgroundActivitySession?
  
  @MainActor
  private final class LocationActivityToken: BackgroundLocationToken {
    let id: UUID
    private let onDeinit: @Sendable (UUID) -> Void
    private var isInvalidated = false
    
    init(id: UUID, onDeinit: @escaping @Sendable (UUID) -> Void) {
      self.id = id
      self.onDeinit = onDeinit
    }
    
    func invalidate() {
      guard !isInvalidated else { return }
      isInvalidated = true
      onDeinit(id)
    }
    
    // Swift 6: deinit on an actor-isolated class is always nonisolated.
    // We delegate the cleanup to a @Sendable closure injected during initialization
    // to guarantee safe execution without breaking actor boundaries.
    nonisolated deinit {
      onDeinit(id)
    }
  }
  
  func requestBackgroundLocation() -> any BackgroundLocationToken {
    let tokenID = UUID()
    let token = LocationActivityToken(id: tokenID) { @Sendable [weak self] id in
      guard let service = self else { return }
      Task { @MainActor in
        service.releaseBackgroundToken(id: id)
      }
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
    
    // Modern iOS 17/18 background management:
    // CLBackgroundActivitySession manages background privileges and the system indicator
    // declaratively, avoiding conflicting legacy flags (allowsBackgroundLocationUpdates).
    if needsBackground && backgroundActivitySession == nil {
      backgroundActivitySession = CLBackgroundActivitySession()
    } else if !needsBackground {
      backgroundActivitySession?.invalidate()
      backgroundActivitySession = nil
    }
  }
  
  func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {
    let meters = distance.converted(to: .meters).value
    guard meters > 0 else {
      Logger.telemetry.warning("Invalid distance filter requested by \(identifier, privacy: .public): \(meters)m. Must be > 0.")
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
    guard updateTask == nil else { return }

    // iOS 18 Declarative Authorization:
    // Retains an active CLServiceSession while streaming to ensure in-use privileges persist.
    if serviceSession == nil {
      serviceSession = CLServiceSession(authorization: .whenInUse)
    }

    // Starts hardware tracking in locationd so distanceFilter and background updates remain active.
    locationManager.startUpdatingLocation()

    Logger.telemetry.info("Starting CLLocationUpdate.liveUpdates(.otherNavigation)")
    updateTask = Task { [weak self] in
      do {
        // Apple's CLLocationUpdate.Updates iterator is throwing (mutating func next() async throws -> CLLocationUpdate?).
        // Therefore, 'for try await' and do-catch are mandatory in Swift to catch system errors (e.g., location disabled).
        let updates = CLLocationUpdate.liveUpdates(.otherNavigation)
        for try await update in updates {
          guard !Task.isCancelled else { break }
          guard let self = self else { break }

          if let location = update.location {
            self.processLocation(location)
          }
        }
      } catch {
        guard !Task.isCancelled else { return }
        guard let self = self else { return }
        Logger.telemetry.error("CLLocationUpdate stream failed with error: \(error.localizedDescription, privacy: .public)")
        for continuation in self.locationContinuations.values {
          continuation.yield(.lost(error))
        }
      }
    }
  }
  
  private func stopUpdatingLocation() {
    Logger.telemetry.info("Stopping CLLocationUpdate.liveUpdates")
    updateTask?.cancel()
    updateTask = nil
    locationManager.stopUpdatingLocation()
    serviceSession?.invalidate()
    serviceSession = nil
  }
  
  private func processLocation(_ latestLocation: CLLocation) {
    let accuracy = latestLocation.horizontalAccuracy
    
    // 1. Drop strictly invalid coordinates (Apple API definition)
    guard accuracy >= 0 else {
      Logger.telemetry.warning("CoreLocationPositioningService dropped strictly invalid coordinate (accuracy < 0)")
      return 
    }
    
    // 2. Mark as degraded if accuracy is poor, but coordinate is physically valid
    let isDegraded = accuracy > 50
    
    if isDegraded {
      Logger.telemetry.warning("CoreLocationPositioningService coordinates are degraded: \(accuracy, privacy: .public)m")
    }
    
    let rawCourse = latestLocation.course
    var courseOverGround: Measurement<UnitAngle>?
    if rawCourse >= 0 && latestLocation.courseAccuracy >= 0 {
      courseOverGround = Measurement(value: rawCourse, unit: .degrees)
    }
    
    var speedOverGround: Measurement<UnitSpeed>?
    var speedOverGroundAccuracy: Measurement<UnitSpeed>?
    if latestLocation.speedAccuracy >= 0 {
      speedOverGround = Measurement(value: latestLocation.speed, unit: .metersPerSecond)
      speedOverGroundAccuracy = Measurement(value: latestLocation.speedAccuracy, unit: .metersPerSecond)
    }
    
    let filteredLocation = NavigationFix(
      coordinate: latestLocation.coordinate,
      horizontalAccuracy: Measurement(value: accuracy, unit: .meters),
      courseOverGround: courseOverGround,
      courseOverGroundAccuracy: (latestLocation.courseAccuracy >= 0) ? Measurement(value: latestLocation.courseAccuracy, unit: .degrees) : nil,
      speedOverGround: speedOverGround,
      speedOverGroundAccuracy: speedOverGroundAccuracy,
      timestamp: latestLocation.timestamp
    )
    
    self.lastKnownLocation = filteredLocation
    
    let state: PositioningState = isDegraded ? .degraded(filteredLocation) : .active(filteredLocation)
    for continuation in locationContinuations.values {
      continuation.yield(state)
    }
  }

  // MARK: - CLLocationManagerDelegate

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      for continuation in authContinuations.values {
        continuation.yield(manager.authorizationStatus)
      }
      
      switch manager.authorizationStatus {
      case .authorizedWhenInUse, .authorizedAlways:
        if !activeUpdateTokens.isEmpty {
          startUpdatingLocation()
        }
      default:
        stopUpdatingLocation()
      }
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Logger.telemetry.error("CoreLocationPositioningService failed with error: \(error.localizedDescription, privacy: .public)")
    Task { @MainActor in
      for continuation in locationContinuations.values {
        continuation.yield(.lost(error))
      }
    }
  }
}
