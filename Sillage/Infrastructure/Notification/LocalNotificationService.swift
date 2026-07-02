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
public class LocalNotificationService: NSObject, NotificationService, UNUserNotificationCenterDelegate {
  
  public override init() {
    super.init()
    UNUserNotificationCenter.current().delegate = self
  }
  
  public func requestAuthorization() async throws -> Bool {
    let center = UNUserNotificationCenter.current()
    let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
    if granted {
      Logger.system.info("User granted local notification permissions.")
    } else {
      Logger.system.warning("User denied local notification permissions.")
    }
    return granted
  }
  
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
    content.sound = UNNotificationSound.defaultCritical // Try to use critical sound, fallbacks to default
    
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    
    do {
      try await center.add(request)
      Logger.system.info("Successfully scheduled local notification: \(identifier)")
    } catch {
      Logger.system.error("Failed to schedule local notification \(identifier): \(error.localizedDescription)")
    }
  }
  
  // MARK: - UNUserNotificationCenterDelegate
  
  // Ensures the notification banner and sound trigger even if the app is currently open and active on the screen.
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    return [.banner, .sound, .badge]
  }
}
