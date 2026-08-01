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
  
  private final class TaskCancellable: @unchecked Sendable {
    var task: Task<Void, Never>?
    deinit { task?.cancel() }
  }
  private let locationFunnelTask = TaskCancellable()
  
  private var requestedFilters: [String: Double] = [:]
  
  override init() {
    let (stream, continuation) = AsyncStream.makeStream(of: [CLLocation].self)
    self.rawLocationContinuation = continuation
    
    self.locationManager = CLLocationManager()
    super.init()
    
    self.locationFunnelTask.task = Task { @MainActor [weak self] in
      for await locations in stream {
        guard let self = self else { break }
        for location in locations {
          self.processLocation(location)
        }
      }
    }
    
    self.locationManager.delegate = self
    
    // Prioritize accuracy over battery for a marine environment.
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    self.locationManager.distanceFilter = PositioningConfig.defaultDistanceFilter
    
    // Marine Activity Type: Crucial to prevent iOS from aggressively snapping
    // coordinates to the nearest coastal road (automotive algorithm).
    self.locationManager.activityType = .otherNavigation
    
    // Auto-Pause and Background Execution are managed dynamically based on active tokens.
    self.locationManager.pausesLocationUpdatesAutomatically = true
    self.locationManager.allowsBackgroundLocationUpdates = false
    self.locationManager.showsBackgroundLocationIndicator = false
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
    locationManager.pausesLocationUpdatesAutomatically = !needsBackground
    locationManager.allowsBackgroundLocationUpdates = needsBackground
    locationManager.showsBackgroundLocationIndicator = needsBackground
    
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
    locationManager.requestWhenInUseAuthorization()
  }
  
  func startUpdatingLocation() {
    locationManager.startUpdatingLocation()
  }
  
  func stopUpdatingLocation() {
    locationManager.stopUpdatingLocation()
  }
  
  // MARK: - CLLocationManagerDelegate
  
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      for continuation in authContinuations.values {
        continuation.yield(manager.authorizationStatus)
      }
      
      switch manager.authorizationStatus {
      case .authorizedWhenInUse, .authorizedAlways:
        startUpdatingLocation()
      default:
        stopUpdatingLocation()
      }
    }
  }
  
  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    // Funnel through an AsyncStream to guarantee sequential, deterministic processing on the MainActor
    rawLocationContinuation.yield(locations)
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
  
  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // OSLog is natively thread-safe. No actor hop required.
    Logger.telemetry.error("CoreLocationPositioningService failed with error: \(error.localizedDescription, privacy: .public)")
    Task { @MainActor in
      for continuation in locationContinuations.values {
        continuation.yield(.lost(error))
      }
    }
  }
}
