//
//  MockNotificationService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
@testable import Sillage

@MainActor
final class MockNotificationService: NotificationService {
  var sentNotifications: [(title: String, body: String, identifier: String)] = []
  
  func sendNotification(title: String, body: String, identifier: String, delay: TimeInterval? = nil) async throws {
    sentNotifications.append((title, body, identifier))
  }
  
  func sendCriticalNotification(title: String, body: String, identifier: String, delay: TimeInterval? = nil) async {
    sentNotifications.append((title, body, identifier))
  }
  
  func clearAllNotifications() {}
  
  func cancelNotification(identifier: String) {}
  
  func checkIn(identifier: String, title: String, body: String, timeout: TimeInterval) async {}
  func cancelWatchdog(identifier: String) async {}
}
