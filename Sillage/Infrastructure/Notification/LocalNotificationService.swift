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
    UNUserNotificationCenter.current().setNotificationCategories(Self.notificationCategories())
  }

  static func notificationCategories() -> Set<UNNotificationCategory> {
    let silenceAction = UNNotificationAction(
      identifier: NotificationIntent.anchorActionSilence.rawValue,
      title: String(localized: "🔇 Silence"),
      options: [.destructive]
    )

    let anchorDraggingCategory = UNNotificationCategory(
      identifier: NotificationIntent.anchorDragging.rawValue,
      actions: [silenceAction],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )

    return [anchorDraggingCategory]
  }

  public func sendNotification(
    title: String,
    body: String,
    identifier: String,
    delay: TimeInterval? = nil
  ) async throws {
    try await scheduleNotification(
      title: title,
      body: body,
      identifier: identifier,
      delay: delay,
      isCritical: false
    )
  }

  public func sendCriticalNotification(
    title: String,
    body: String,
    identifier: String,
    delay: TimeInterval? = nil
  ) async throws {
    try await scheduleNotification(
      title: title,
      body: body,
      identifier: identifier,
      delay: delay,
      isCritical: true
    )
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
    Logger.system.info("Cancelled notification: \(identifier, privacy: .public)")
  }

  private func scheduleNotification(
    title: String,
    body: String,
    identifier: String,
    delay: TimeInterval?,
    isCritical: Bool
  ) async throws {
    let center = UNUserNotificationCenter.current()

    // Idempotency: clear existing pending requests with the same identifier
    center.removePendingNotificationRequests(withIdentifiers: [identifier])

    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
      Logger.system.warning("Cannot send notification '\(identifier, privacy: .public)': not authorized.")
      throw NotificationError.permissionDenied
    }

    let content = makeNotificationContent(
      title: title,
      body: body,
      identifier: identifier,
      settings: settings,
      isCritical: isCritical
    )

    let trigger: UNNotificationTrigger?
    if let delay, delay > 0 {
      trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
    } else {
      trigger = nil
    }

    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

    do {
      try await center.add(request)
      Logger.system.info("Successfully scheduled \(isCritical ? "critical" : "local", privacy: .public) notification: \(identifier, privacy: .public)")
    } catch {
      Logger.system.error("Failed to schedule \(isCritical ? "critical" : "local", privacy: .public) notification \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
      throw NotificationError.schedulingFailed(error.localizedDescription)
    }
  }

  private func makeNotificationContent(
    title: String,
    body: String,
    identifier: String,
    settings: UNNotificationSettings,
    isCritical: Bool
  ) -> UNMutableNotificationContent {
    Self.makeNotificationContent(
      title: title,
      body: body,
      identifier: identifier,
      isCritical: isCritical,
      isCriticalAuthorized: settings.criticalAlertSetting == .enabled,
      isTimeSensitiveAuthorized: settings.timeSensitiveSetting == .enabled
    )
  }

  static func makeNotificationContent(
    title: String,
    body: String,
    identifier: String,
    isCritical: Bool,
    isCriticalAuthorized: Bool,
    isTimeSensitiveAuthorized: Bool
  ) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.categoryIdentifier = identifier

    guard isCritical else {
      content.sound = UNNotificationSound.default
      content.interruptionLevel = .active
      return content
    }

    if identifier == NotificationIntent.anchorDragging.rawValue {
      let anchorSoundName = UNNotificationSoundName("AnchorAlarm_CleanEscalation_27s.wav")
      content.sound = isCriticalAuthorized
        ? UNNotificationSound.criticalSoundNamed(anchorSoundName, withAudioVolume: 1.0)
        : UNNotificationSound(named: anchorSoundName)
    } else {
      content.sound = isCriticalAuthorized
        ? UNNotificationSound.defaultCriticalSound(withAudioVolume: 1.0)
        : UNNotificationSound.default
    }

    if isCriticalAuthorized {
      content.interruptionLevel = .critical
    } else if isTimeSensitiveAuthorized {
      content.interruptionLevel = .timeSensitive
      Logger.system.warning("Critical alert permission disabled/unsupported for '\(identifier, privacy: .public)'; using .timeSensitive interruption level.")
    } else {
      content.interruptionLevel = .active
      Logger.system.warning("Neither criticalAlert nor timeSensitive is enabled for '\(identifier, privacy: .public)'; falling back to .active interruption level.")
    }

    return content
  }
}
