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

/// Errors that can occur during notification scheduling.
public enum NotificationError: LocalizedError, Equatable {
    case permissionDenied
    case schedulingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notifications are disabled. Please enable them in Settings."
        case .schedulingFailed(let message):
            return "Failed to schedule notification: \(message)"
        }
    }
}

/// Defines the contract for sending local or remote notifications.
public protocol NotificationService: Sendable {
  
  /// Sends a local notification to the user.
  /// - Parameters:
  ///   - title: The title of the notification.
  ///   - body: The body message.
  ///   - identifier: A unique identifier for the request. If a notification with the same identifier is already pending, it will be replaced.
  ///   - delay: Optional delay in seconds before the notification is triggered.
  func sendNotification(title: String, body: String, identifier: String, delay: TimeInterval?) async throws
  
  /// Sends a critical local notification to the user (bypasses silent switch).
  /// - Parameters:
  ///   - title: The title of the notification.
  ///   - body: The body message.
  ///   - identifier: A unique identifier for the request.
  func sendCriticalNotification(title: String, body: String, identifier: String) async
  
  /// Clears all pending and delivered notifications from the notification center.
  func clearAllNotifications()
  
  /// Cancels a specific pending notification.
  /// - Parameter identifier: The unique identifier of the notification to cancel.
  func cancelNotification(identifier: String)
  
  /// Registers a check-in for a watchdog notification.
  /// Throttles requests automatically (e.g. 60 seconds) to save CPU/battery.
  func checkIn(identifier: String, title: String, body: String, timeout: TimeInterval) async
  
  /// Cancels a pending watchdog notification.
  func cancelWatchdog(identifier: String) async
}
