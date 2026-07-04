//
//  NotificationService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Defines the contract for sending local or remote notifications.
public protocol NotificationService: Sendable {
  
  /// Requests authorization from the user to display notifications.
  /// - Returns: True if authorization is granted, false otherwise.
  @discardableResult
  func requestAuthorization() async throws -> Bool
  
  /// Sends a local notification to the user.
  /// - Parameters:
  ///   - title: The title of the notification.
  ///   - body: The body message.
  ///   - identifier: A unique identifier for the request. If a notification with the same identifier is already pending, it will be replaced.
  func sendNotification(title: String, body: String, identifier: String) async
  
  /// Requests authorization from the user to display critical notifications.
  /// - Returns: True if authorization is granted, false otherwise.
  @discardableResult
  func requestCriticalAuthorization() async throws -> Bool
  
  /// Sends a critical local notification to the user (bypasses silent switch).
  /// - Parameters:
  ///   - title: The title of the notification.
  ///   - body: The body message.
  ///   - identifier: A unique identifier for the request.
  func sendCriticalNotification(title: String, body: String, identifier: String) async
  
  /// Clears all delivered notifications from the notification center.
  func clearDeliveredNotifications()
}
