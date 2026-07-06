//
//  LocalNotificationService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import UserNotifications
import OSLog

/// Concrete implementation of NotificationService using iOS local notifications.
public struct LocalNotificationService: NotificationService {
  
  public init() {}
  

  
  public func sendNotification(title: String, body: String, identifier: String) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
      Logger.system.debug("Cannot send notification '\(identifier)': not authorized.")
      return
    }
    
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = UNNotificationSound.default
    
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    
    do {
      try await center.add(request)
      Logger.system.info("Successfully scheduled local notification: \(identifier)")
    } catch {
      Logger.system.error("Failed to schedule local notification \(identifier): \(error.localizedDescription)")
    }
  }
  

  
  public func sendCriticalNotification(title: String, body: String, identifier: String) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
      Logger.system.debug("Cannot send critical notification '\(identifier)': not authorized.")
      return
    }
    
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = UNNotificationSound.defaultCritical
    
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    
    do {
      try await center.add(request)
      Logger.system.info("Successfully scheduled critical notification: \(identifier)")
    } catch {
      Logger.system.error("Failed to schedule critical notification \(identifier): \(error.localizedDescription)")
    }
  }
  
  public func clearAllNotifications() {
    let center = UNUserNotificationCenter.current()
    center.removeAllDeliveredNotifications()
    center.removeAllPendingNotificationRequests()
    Logger.system.info("Cleared all notifications.")
  }
}
