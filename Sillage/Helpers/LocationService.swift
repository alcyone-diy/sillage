//
//  LocationService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

protocol LocationServiceProtocol {
  var locationUpdates: AsyncStream<CLLocation> { get }
  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> { get }

  func requestAuthorization()
  func startUpdatingLocation()
  func stopUpdatingLocation()
}

class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {

  static let shared = LocationService()

  private let locationManager: CLLocationManager

  // Multicast support for Location Updates
  private var locationContinuations: [UUID: AsyncStream<CLLocation>.Continuation] = [:]
  private let locationContinuationsLock = NSLock()
  var locationUpdates: AsyncStream<CLLocation> {
    let (stream, continuation) = AsyncStream.makeStream(of: CLLocation.self)
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
  private var authContinuations: [UUID: AsyncStream<CLAuthorizationStatus>.Continuation] = [:]
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
  private var lastSmoothedCourse: CLLocationDirection = -1.0
  private var courseBuffer: [CLLocationDirection] = []
  private let maxBufferSize = 4

  // Speed thresholds
  private let cutOffSpeed: CLLocationSpeed = Measurement(value: 0.8, unit: UnitSpeed.knots).converted(to: .metersPerSecond).value
  private let resumeSpeed: CLLocationSpeed = Measurement(value: 1.5, unit: UnitSpeed.knots).converted(to: .metersPerSecond).value

  private override init() {
    self.locationManager = CLLocationManager()
    super.init()

    self.locationManager.delegate = self
    // Prioritize accuracy over battery for a marine environment
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    self.locationManager.distanceFilter = kCLDistanceFilterNone

    // Marine Activity Type: prevents automotive road-snapping algorithms
    self.locationManager.activityType = .otherNavigation

    // TODO: Disable pausesLocationUpdatesAutomatically when needed.
    // Disable Auto-Pause: never pause updates
    // self.locationManager.pausesLocationUpdatesAutomatically = false

    // TODO: Enable background when needed.
    // Background Execution
    // self.locationManager.allowsBackgroundLocationUpdates = true
    // self.locationManager.showsBackgroundLocationIndicator = true
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

    // Filter out inaccurate GPS points (horizontal accuracy > 50m or invalid < 0)
    let accuracy = latestLocation.horizontalAccuracy
    if accuracy >= 0 && accuracy <= 50 {

      let speed = latestLocation.speed

      // Hysteresis State Machine
      if movementState == .moving && speed >= 0 && speed < cutOffSpeed {
        movementState = .stopped
      } else if movementState == .stopped && speed >= resumeSpeed {
        movementState = .moving
      }

      var finalCourse = lastSmoothedCourse

      if movementState == .moving {
        let rawCourse = latestLocation.course
        if rawCourse >= 0 {
          courseBuffer.append(rawCourse)
          if courseBuffer.count > maxBufferSize {
            courseBuffer.removeFirst()
          }

          var sumX = 0.0
          var sumY = 0.0

          for c in courseBuffer {
            let radians = c * .pi / 180.0
            sumX += cos(radians)
            sumY += sin(radians)
          }

          let avgX = sumX / Double(courseBuffer.count)
          let avgY = sumY / Double(courseBuffer.count)

          var smoothedAngle = atan2(avgY, avgX) * 180.0 / .pi
          if smoothedAngle < 0 {
            smoothedAngle += 360.0
          }

          finalCourse = smoothedAngle
          lastSmoothedCourse = smoothedAngle
        } else {
          // invalid course received while moving
          finalCourse = lastSmoothedCourse
        }
      }

      let filteredLocation = CLLocation(
        coordinate: latestLocation.coordinate,
        altitude: latestLocation.altitude,
        horizontalAccuracy: latestLocation.horizontalAccuracy,
        verticalAccuracy: latestLocation.verticalAccuracy,
        course: finalCourse,
        courseAccuracy: latestLocation.courseAccuracy,
        speed: latestLocation.speed,
        speedAccuracy: latestLocation.speedAccuracy,
        timestamp: latestLocation.timestamp
      )

      locationContinuationsLock.lock()
      for continuation in locationContinuations.values {
        continuation.yield(filteredLocation)
      }
      locationContinuationsLock.unlock()
    } else {
      print("LocationService ignored coordinate due to low accuracy: \(accuracy)m")
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("LocationService failed with error: \(error.localizedDescription) (Ensure Simulator -> Features -> Location is set)")
  }
}
