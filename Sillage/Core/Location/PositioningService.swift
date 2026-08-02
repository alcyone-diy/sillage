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
  
  func requestBackgroundLocation() -> any BackgroundLocationToken
  func requestLocationUpdates() -> any LocationUpdateToken
  
  func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String)
  func removeDistanceFilter(for identifier: String)
}
