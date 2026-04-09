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
import Combine

protocol LocationServiceProtocol {
  var locationPublisher: PassthroughSubject<CLLocation, Never> { get }
  var authorizationStatusPublisher: PassthroughSubject<CLAuthorizationStatus, Never> { get }

  func requestAuthorization()
  func startUpdatingLocation()
  func stopUpdatingLocation()
}

class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {

  static let shared = LocationService()

  private let locationManager: CLLocationManager

  let locationPublisher = PassthroughSubject<CLLocation, Never>()
  let authorizationStatusPublisher = PassthroughSubject<CLAuthorizationStatus, Never>()

  // MARK: - State variables for Heading Stabilization
  private enum MovementState {
    case moving
    case stopped
  }

  private var movementState: MovementState = .stopped
  private var lastSmoothedCourse: CLLocationDirection = -1.0
  private var courseBuffer: [CLLocationDirection] = []
  private let maxBufferSize = 4

  // Speed thresholds in m/s (1 knot = 0.514444 m/s)
  private let cutOffSpeed: CLLocationSpeed = 0.8 * 0.514444
  private let resumeSpeed: CLLocationSpeed = 1.5 * 0.514444

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
    authorizationStatusPublisher.send(manager.authorizationStatus)

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

      locationPublisher.send(filteredLocation)
    } else {
      print("LocationService ignored coordinate due to low accuracy: \(accuracy)m")
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("LocationService failed with error: \(error.localizedDescription) (Ensure Simulator -> Features -> Location is set)")
  }
}
