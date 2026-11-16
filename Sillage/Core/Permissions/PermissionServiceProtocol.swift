//
//  PermissionServiceProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import UserNotifications

/// Availability of an individual system notification capability (such as Critical Alerts or Time Sensitive alerts).
public nonisolated enum NotificationAlertCapabilityStatus: Sendable, Equatable {
  case unknown
  case notSupported
  case disabled
  case enabled
}

/// Thread-safe snapshot of `UNNotificationSettings` fields needed by the permission layer and tests.
public nonisolated struct NotificationSettingsSnapshot: Sendable, Equatable {
  public let authorizationStatus: UNAuthorizationStatus
  public let criticalAlertSetting: UNNotificationSetting
  public let timeSensitiveSetting: UNNotificationSetting

  public init(
    authorizationStatus: UNAuthorizationStatus,
    criticalAlertSetting: UNNotificationSetting,
    timeSensitiveSetting: UNNotificationSetting
  ) {
    self.authorizationStatus = authorizationStatus
    self.criticalAlertSetting = criticalAlertSetting
    self.timeSensitiveSetting = timeSensitiveSetting
  }
}

/// Abstraction over `UNUserNotificationCenter` permission APIs so authorization flows remain testable without system XPC calls.
public nonisolated protocol NotificationAuthorizationProviding: Sendable {
  func notificationSettings() async -> NotificationSettingsSnapshot
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

public nonisolated struct SystemNotificationAuthorizationProvider: NotificationAuthorizationProviding {
  public init() {}

  public func notificationSettings() async -> NotificationSettingsSnapshot {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    return NotificationSettingsSnapshot(
      authorizationStatus: settings.authorizationStatus,
      criticalAlertSetting: settings.criticalAlertSetting,
      timeSensitiveSetting: settings.timeSensitiveSetting
    )
  }

  public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    try await UNUserNotificationCenter.current().requestAuthorization(options: options)
  }
}

@MainActor
public protocol PermissionServiceProtocol: AnyObject {
  var locationStatus: PermissionStatus { get }
  var notificationStatus: PermissionStatus { get }
  var criticalAlertStatus: NotificationAlertCapabilityStatus { get }
  var timeSensitiveStatus: NotificationAlertCapabilityStatus { get }
  var motionStatus: PermissionStatus { get }

  func requestLocationAuthorization() async
  func requestNotificationAuthorization() async -> Bool
  func requestCriticalNotificationAuthorization() async -> Bool
  func requestMotionAuthorization() async
  func openSystemSettings()
}
