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
  var locationUpdates: AsyncStream<NavigationFix> { get }
  var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> { get }

  func requestAuthorization()
  func startUpdatingLocation()
  func stopUpdatingLocation()
  
  func requestBackgroundLocation() -> any BackgroundLocationToken
}
