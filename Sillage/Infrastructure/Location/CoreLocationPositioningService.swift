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
  
  // MARK: - Multicast Streams
  
  private var locationContinuations: [UUID: AsyncStream<NavigationFix>.Continuation] = [:]
  
  var locationUpdates: AsyncStream<NavigationFix> {
    let (stream, continuation) = AsyncStream.makeStream(of: NavigationFix.self)
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
  
  // MARK: - Heading Stabilization State
  
  private enum MovementState {
    case moving
    case stopped
  }
  
  private var movementState: MovementState = .stopped
  private var lastSmoothedCourseOverGround: Measurement<UnitAngle>?
  private var courseOverGroundBuffer: [CLLocationDirection] = []
  
  // The buffer size dictates the smoothing window. 4 updates (~4 seconds) provides
  // a good balance between stability and responsiveness during a tack or jibe.
  private let maxBufferSize = 4
  
  // Speed thresholds for the Hysteresis State Machine.
  // Using hysteresis prevents the boat icon from wildly spinning (GPS jitter)
  // when moving very slowly or docked.
  private let cutOffSpeed: CLLocationSpeed = Measurement(value: 0.8, unit: UnitSpeed.knots).converted(to: .metersPerSecond).value
  private let resumeSpeed: CLLocationSpeed = Measurement(value: 1.5, unit: UnitSpeed.knots).converted(to: .metersPerSecond).value
  
  override init() {
    self.locationManager = CLLocationManager()
    super.init()
    
    self.locationManager.delegate = self
    
    // Prioritize accuracy over battery for a marine environment.
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    self.locationManager.distanceFilter = kCLDistanceFilterNone
    
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
  
  func requestAuthorization() {
    locationManager.requestWhenInUseAuthorization()
  }
  
  private var locationUpdateTask: Task<Void, Never>?
  
  func startUpdatingLocation() {
    locationUpdateTask?.cancel()
    locationUpdateTask = Task { @MainActor [weak self] in
      do {
        let updates = CLLocationUpdate.liveUpdates(.otherNavigation)
        for try await update in updates {
          guard let self = self else { return }
          if let location = update.location {
            self.processLocation(location)
          }
        }
      } catch {
        Logger.telemetry.error("CoreLocationPositioningService failed with error: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
  
  func stopUpdatingLocation() {
    locationUpdateTask?.cancel()
    locationUpdateTask = nil
  }
  
  // MARK: - CLLocationManagerDelegate
  
  // Delegate methods are nonisolated to satisfy Objective-C interoperability.
  // We explicitly hop to the @MainActor to update our state.
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
  
  private func processLocation(_ latestLocation: CLLocation) {
    // Filter out inaccurate GPS points (horizontal accuracy > 50m or invalid < 0).
    let accuracy = latestLocation.horizontalAccuracy
    guard accuracy >= 0 && accuracy <= 50 else {
      Logger.telemetry.warning("CoreLocationPositioningService ignored coordinate due to low accuracy: \(accuracy, privacy: .public)m")
      return
    }
    
    let speed = latestLocation.speed
    
    // Hysteresis State Machine: Update movement state based on speed thresholds
    if movementState == .moving && speed >= 0 && speed < cutOffSpeed {
      movementState = .stopped
    } else if movementState == .stopped && speed >= resumeSpeed {
      movementState = .moving
    }
    
    var finalCourseOverGround = lastSmoothedCourseOverGround
    
    if movementState == .moving {
      let rawCourse = latestLocation.course
      if rawCourse >= 0 && latestLocation.courseAccuracy >= 0 {
        courseOverGroundBuffer.append(rawCourse)
        if courseOverGroundBuffer.count > maxBufferSize {
          courseOverGroundBuffer.removeFirst()
        }
        
        var sumX = 0.0
        var sumY = 0.0
        
        // Vector-based average of the course over ground.
        // This mathematically solves the 359° to 1° wrap-around issue which would
        // incorrectly average to 180° using standard arithmetic.
        for c in courseOverGroundBuffer {
          let radians = c * .pi / 180.0
          sumX += cos(radians)
          sumY += sin(radians)
        }
        
        let avgX = sumX / Double(courseOverGroundBuffer.count)
        let avgY = sumY / Double(courseOverGroundBuffer.count)
        
        var smoothedAngleOverGround = atan2(avgY, avgX)
        if smoothedAngleOverGround < 0 {
          smoothedAngleOverGround += .pi * 2
        }
        
        finalCourseOverGround = Measurement(value: smoothedAngleOverGround, unit: .radians)
        lastSmoothedCourseOverGround = finalCourseOverGround
      } else {
#if DEBUG
        // Debug value to understand why the cog is not updated.
        finalCourseOverGround = Measurement(value: 1, unit: .gradians)
#else
        // Fallback to the last known good course if GPS briefly loses course accuracy while moving
        finalCourseOverGround = lastSmoothedCourseOverGround
#endif
      }
    } else {
#if DEBUG
      // Debug value to understand why the cog is not updated.
      finalCourseOverGround = Measurement(value: 2, unit: .gradians)
#endif
    }
    
    var speedOverGround: Measurement<UnitSpeed>?
    var speedOverGroundAccuracy: Measurement<UnitSpeed>?
    if latestLocation.speedAccuracy >= 0 {
      speedOverGround = Measurement(value: latestLocation.speed, unit: .metersPerSecond)
      speedOverGroundAccuracy = Measurement(value: latestLocation.speedAccuracy, unit: .metersPerSecond)
    }
    
    let filteredLocation = NavigationFix(
      coordinate: latestLocation.coordinate,
      horizontalAccuracy: Measurement(value: latestLocation.horizontalAccuracy, unit: .meters),
      courseOverGround: finalCourseOverGround,
      courseOverGroundAccuracy: (latestLocation.courseAccuracy >= 0) ? Measurement(value: latestLocation.courseAccuracy, unit: .degrees) : nil,
      speedOverGround: speedOverGround,
      speedOverGroundAccuracy: speedOverGroundAccuracy,
      timestamp: latestLocation.timestamp
    )
    
    for continuation in locationContinuations.values {
      continuation.yield(filteredLocation)
    }
  }
  
  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // OSLog is natively thread-safe. No actor hop required.
    Logger.telemetry.error("CoreLocationPositioningService failed with error: \(error.localizedDescription, privacy: .public)")
  }
}
