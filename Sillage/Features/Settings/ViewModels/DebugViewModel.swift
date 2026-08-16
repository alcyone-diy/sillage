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
import UIKit
import Observation
import OSLog

@Observable
@MainActor
final class DebugViewModel {
  
  func invalidateGeoGarageToken() {
    KeychainManager.shared.saveSync(token: "invalid_debug_token", for: "geogarage_access_token")
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
      identifier: NotificationIntent.barometerDrop.rawValue,
      delay: 5.0
    )
  }
  
  func scheduleDebugAnchorNotification(
    permissionService: PermissionServiceProtocol,
    notificationService: NotificationService,
    anchorService: AnchorService
  ) async throws {
    let granted = await permissionService.requestCriticalNotificationAuthorization()
    guard granted else {
      throw NotificationError.permissionDenied
    }
    
    anchorService.alarmAudioService.prepareAudioSession()
    
    await notificationService.sendCriticalNotification(
      title: "⚓️ DRAGGING ANCHOR! (Debug)",
      body: "Vessel is out of the safe zone (42m / 30m max).",
      identifier: NotificationIntent.anchorDragging.rawValue,
      delay: 5.0
    )
    
    Task { @MainActor [weak anchorService] in
      var bgTaskID: UIBackgroundTaskIdentifier = .invalid
      bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "DebugAnchorAlarm") {
        if bgTaskID != .invalid {
          UIApplication.shared.endBackgroundTask(bgTaskID)
          bgTaskID = .invalid
        }
      }
      
      defer {
        if bgTaskID != .invalid {
          UIApplication.shared.endBackgroundTask(bgTaskID)
          bgTaskID = .invalid
        }
      }
      
      do {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        guard let anchorService = anchorService else { return }
        anchorService.simulateDebugDragging()
        anchorService.alarmAudioService.startSiren()
      } catch {
        Logger.anchor.info("Debug anchor alarm task cancelled: \(error.localizedDescription)")
      }
    }
  }


  // MARK: - GPS Accuracy (Debug)

  func setGPSAccuracyMode(_ mode: GPSAccuracyMode, appEnvironment: AppEnvironment) {
    appEnvironment.updateGPSAccuracy(to: mode)
  }



}

