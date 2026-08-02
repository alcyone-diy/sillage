//
//  DebugViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class DebugViewModel {
  
  func invalidateGeoGarageToken() {
    KeychainManager.shared.save(token: "invalid_debug_token", for: "geogarage_access_token")
  }
  
  func scheduleDebugBarometerNotification(permissionService: PermissionServiceProtocol, notificationService: NotificationService) async throws {
    // Check current status
    let currentStatus = permissionService.notificationStatus
    
    if currentStatus == .denied {
      throw NotificationError.permissionDenied
    }
    
    // Request if not determined
    if currentStatus != .authorized {
      let granted = await permissionService.requestNotificationAuthorization()
      guard granted else {
        throw NotificationError.permissionDenied
      }
    }
    
    // Actually schedule
    try await notificationService.sendNotification(
      title: "DEBUG: Weather Alarm",
      body: "A rapid pressure drop has been detected (Debug).",
      identifier: "sillage.barometer.debug",
      delay: 5.0
    )
  }
}
