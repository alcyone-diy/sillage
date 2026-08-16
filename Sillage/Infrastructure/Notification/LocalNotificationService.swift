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
  
  public init() {
    registerNotificationCategories()
  }
  
  private func registerNotificationCategories() {
    let silenceAction = UNNotificationAction(
      identifier: NotificationIntent.anchorActionSilence.rawValue,
      title: String(localized: "🔇 Silence"),
      options: [.authenticationRequired]
    )
    
    let anchorDraggingCategory = UNNotificationCategory(
      identifier: NotificationIntent.anchorDragging.rawValue,
      actions: [silenceAction],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )
    
    UNUserNotificationCenter.current().setNotificationCategories([anchorDraggingCategory])
  }

  public func sendNotification(title: String, body: String, identifier: String, delay: TimeInterval? = nil) async throws {
    let center = UNUserNotificationCenter.current()
    
    // Idempotency: clear existing requests with the same identifier
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    
    let settings = await center.notificationSettings()
    
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
      Logger.system.debug("Cannot send notification '\(identifier)': not authorized.")
      return
    }
    
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.categoryIdentifier = identifier
    content.sound = UNNotificationSound.default
    
    let trigger: UNNotificationTrigger?
    if let delay = delay, delay > 0 {
      trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
    } else {
      trigger = nil
    }
    
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    
    do {
      try await center.add(request)
      Logger.system.info("Successfully scheduled local notification: \(identifier)")
    } catch {
      Logger.system.error("Failed to schedule local notification \(identifier): \(error.localizedDescription)")
      throw NotificationError.schedulingFailed(error.localizedDescription)
    }
  }
  
  public func sendCriticalNotification(title: String, body: String, identifier: String, delay: TimeInterval? = nil) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
      Logger.system.debug("Cannot send critical notification '\(identifier)': not authorized.")
      return
    }
    
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.categoryIdentifier = identifier
    
    if settings.criticalAlertSetting == .enabled {
      content.sound = UNNotificationSound.defaultCritical
    } else {
      content.sound = UNNotificationSound.default
    }
    
    let trigger: UNNotificationTrigger?
    if let delay = delay, delay > 0 {
      trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
    } else {
      trigger = nil
    }
    
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    
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
  
  public func cancelNotification(identifier: String) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
    Logger.system.info("Cancelled notification: \(identifier)")
  }
}
