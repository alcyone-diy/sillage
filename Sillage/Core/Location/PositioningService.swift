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

protocol PositioningService {
  var currentAuthorizationStatus: CLAuthorizationStatus { get }
  var locationUpdates: AsyncStream<PositioningState> { get }
  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> { get }
  var currentDistanceFilter: Measurement<UnitLength> { get }

  func requestAuthorization()
  func startUpdatingLocation()
  func stopUpdatingLocation()
  
  func requestBackgroundLocation() -> any BackgroundLocationToken
  
  func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String)
  func removeDistanceFilter(for identifier: String)
}
