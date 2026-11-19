//
//  PositioningService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

@MainActor
public protocol LocationUpdateToken: AnyObject, Sendable {
  func invalidate()
}

protocol PositioningService {
  var currentAuthorizationStatus: CLAuthorizationStatus { get }
  var locationUpdates: AsyncStream<PositioningState> { get }
  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> { get }
  var currentDistanceFilter: Measurement<UnitLength> { get }
  var lastKnownLocation: NavigationFix? { get }

  func requestAuthorization()
  
  /// Acquires an RAII lease enabling background GPS execution while held.
  /// Orthogonal to `requestLocationUpdates()`: callers needing live fixes in the background must hold both tokens.
  func requestBackgroundLocation() -> any BackgroundLocationToken
  /// Acquires an RAII lease keeping hardware location updates active while held.
  func requestLocationUpdates() -> any LocationUpdateToken
  
  func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String)
  func removeDistanceFilter(for identifier: String)

  func setDesiredAccuracy(_ mode: GPSAccuracyMode)
  func setPausesLocationUpdatesAutomatically(_ pauses: Bool)
}

extension PositioningService {
  func setDesiredAccuracy(_ mode: GPSAccuracyMode) {}
  func setPausesLocationUpdatesAutomatically(_ pauses: Bool) {}
}
