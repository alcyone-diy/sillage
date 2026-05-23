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

public protocol BackgroundLocationToken: AnyObject {
  func invalidate()
}

class CoreLocationPositioningService: NSObject, PositioningService, CLLocationManagerDelegate {
  
  private let locationManager: CLLocationManager
  
  // Multicast support for Location Updates
  nonisolated(unsafe) private var locationContinuations: [UUID: AsyncStream<NavigationFix>.Continuation] = [:]
  private let locationContinuationsLock = NSLock()
  var locationUpdates: AsyncStream<NavigationFix> {
    let (stream, continuation) = AsyncStream.makeStream(of: NavigationFix.self)
    let id = UUID()
    locationContinuationsLock.lock()
    locationContinuations[id] = continuation
    locationContinuationsLock.unlock()
    
    continuation.onTermination = { [weak self] _ in
      guard let self = self else { return }
      self.locationContinuationsLock.lock()
      self.locationContinuations.removeValue(forKey: id)
      self.locationContinuationsLock.unlock()
    }
    return stream
  }
  
  // Multicast support for Authorization Status
  nonisolated(unsafe) private var authContinuations: [UUID: AsyncStream<CLAuthorizationStatus>.Continuation] = [:]
  private let authContinuationsLock = NSLock()
  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> {
    let (stream, continuation) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)
    let id = UUID()
    authContinuationsLock.lock()
    authContinuations[id] = continuation
    authContinuationsLock.unlock()
    
    continuation.onTermination = { [weak self] _ in
      guard let self = self else { return }
      self.authContinuationsLock.lock()
      self.authContinuations.removeValue(forKey: id)
      self.authContinuationsLock.unlock()
    }
    return stream
  }
  
  // MARK: - State variables for Heading Stabilization
  private enum MovementState {
    case moving
    case stopped
  }
  
  private var movementState: MovementState = .stopped
  private var lastSmoothedCourseOverGround: Measurement<UnitAngle>?
  private var courseOverGroundBuffer: [CLLocationDirection] = []
  private let maxBufferSize = 4
  
  // Speed thresholds
  private let cutOffSpeed: CLLocationSpeed = Measurement(value: 0.8, unit: UnitSpeed.knots).converted(to: .metersPerSecond).value
  private let resumeSpeed: CLLocationSpeed = Measurement(value: 1.5, unit: UnitSpeed.knots).converted(to: .metersPerSecond).value
  
  override init() {
    self.locationManager = CLLocationManager()
    super.init()
    
    self.locationManager.delegate = self
    // Prioritize accuracy over battery for a marine environment
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    self.locationManager.distanceFilter = kCLDistanceFilterNone
    
    // Marine Activity Type: prevents automotive road-snapping algorithms
    self.locationManager.activityType = .otherNavigation
    
    // Auto-Pause and Background Execution are managed dynamically
    // via setBackgroundActivity(id:isActive:)
    self.locationManager.pausesLocationUpdatesAutomatically = true
    self.locationManager.allowsBackgroundLocationUpdates = false
    self.locationManager.showsBackgroundLocationIndicator = false
  }
  
  // MARK: - Background Activity tracking
  private var activeBackgroundSessions = Set<UUID>()
  private let backgroundSessionsLock = NSLock()
  
  private final class LocationActivityToken: BackgroundLocationToken {
    let id = UUID()
    let onInvalidate: (UUID) -> Void
    private var isInvalidated = false
    private let lock = NSLock()
    
    init(onInvalidate: @escaping (UUID) -> Void) {
      self.onInvalidate = onInvalidate
    }
    
    func invalidate() {
      lock.lock()
      defer { lock.unlock() }
      guard !isInvalidated else { return }
      isInvalidated = true
      onInvalidate(id)
    }
    
    deinit {
      invalidate()
    }
  }
  
  func requestBackgroundLocation() -> any BackgroundLocationToken {
    backgroundSessionsLock.lock()
    defer { backgroundSessionsLock.unlock() }
    
    let token = LocationActivityToken { [weak self] id in
      self?.releaseBackgroundToken(id: id)
    }
    
    activeBackgroundSessions.insert(token.id)
    updateBackgroundLocationStatus()
    
    return token
  }
  
  private func releaseBackgroundToken(id: UUID) {
    backgroundSessionsLock.lock()
    defer { backgroundSessionsLock.unlock() }
    
    activeBackgroundSessions.remove(id)
    updateBackgroundLocationStatus()
  }
  
  private func updateBackgroundLocationStatus() {
    let needsBackground = !activeBackgroundSessions.isEmpty
    locationManager.pausesLocationUpdatesAutomatically = !needsBackground
    locationManager.allowsBackgroundLocationUpdates = needsBackground
    locationManager.showsBackgroundLocationIndicator = needsBackground
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
  
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authContinuationsLock.lock()
    for continuation in authContinuations.values {
      continuation.yield(manager.authorizationStatus)
    }
    authContinuationsLock.unlock()
    
    switch manager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      startUpdatingLocation()
    default:
      stopUpdatingLocation()
    }
  }
  
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let latestLocation = locations.last else { return }
    
    // Filter out inaccurate GPS points (horizontal accuracy > 50m or invalid < 0).
    let accuracy = latestLocation.horizontalAccuracy
    guard accuracy >= 0 && accuracy <= 50 else {
      Logger.telemetry.warning("CoreLocationPositioningService ignored coordinate due to low accuracy: \(accuracy, privacy: .public)m")
      return
    }
    
    let speed = latestLocation.speed
    // Hysteresis State Machine
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
        // invalid course received while moving
        finalCourseOverGround = lastSmoothedCourseOverGround
      }
    }
    
    var speedOverGround: Measurement<UnitSpeed>?
    var speedOverGroundAccuracy: Measurement<UnitSpeed>?
    if latestLocation.speedAccuracy >= 0 {
      speedOverGround = Measurement(value:latestLocation.speed, unit: .metersPerSecond)
      speedOverGroundAccuracy = Measurement(value:latestLocation.speedAccuracy, unit: .metersPerSecond)
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
    
    locationContinuationsLock.lock()
    for continuation in locationContinuations.values {
      continuation.yield(filteredLocation)
    }
    locationContinuationsLock.unlock()
  }
  
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Logger.telemetry.error("CoreLocationPositioningService failed with error: \(error.localizedDescription, privacy: .public) (Ensure Simulator -> Features -> Location is set)")
  }
}
