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

  private override init() {
    self.locationManager = CLLocationManager()
    super.init()

    self.locationManager.delegate = self
    // Prioritize accuracy over battery for a marine environment
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    self.locationManager.distanceFilter = kCLDistanceFilterNone

    // Marine Activity Type: prevents automotive road-snapping algorithms
    self.locationManager.activityType = .otherNavigation

    // Disable Auto-Pause: never pause updates
    self.locationManager.pausesLocationUpdatesAutomatically = false

    // Background Execution
    self.locationManager.allowsBackgroundLocationUpdates = true
    self.locationManager.showsBackgroundLocationIndicator = true
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
      locationPublisher.send(latestLocation)
    } else {
      print("LocationService ignored coordinate due to low accuracy: \(accuracy)m")
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("LocationService failed with error: \(error.localizedDescription) (Ensure Simulator -> Features -> Location is set)")
  }
}
