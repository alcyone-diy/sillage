//
//  MessageService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

/// A service to manage internal app messages.
/// Uses the `@Observable` and `@MainActor` to integrate with SwiftUI UI.
@Observable
@MainActor
public final class MessageService: Sendable {
  public private(set) var messages: [AppMessage] = []
  private let maxMessageCount = 50


  public init() {}

  /// Posts a new message or updates an existing one with the same ID
  /// - Parameter message: The message to post
  public func post(_ message: AppMessage) {
    if let index = messages.firstIndex(where: { $0.id == message.id }) {
      messages.remove(at: index)
      messages.insert(message, at: 0)
      Logger.messaging.info("Updated and promoted existing message by ID [\(message.id, privacy: .public)]")
    } else {
      messages.insert(message, at: 0)
      Logger.messaging.info("Added new message [\(message.id, privacy: .public)]: \(String(localized: message.title), privacy: .public)")
    }
    
    if messages.count > maxMessageCount {
      if let indexToEvict = messages.lastIndex(where: { $0.isDismissable }) {
        let removedMessage = messages.remove(at: indexToEvict)
        Logger.messaging.warning("Limit reached. Evicted dismissable message [\(removedMessage.id, privacy: .public)]")
      } else {
        Logger.messaging.error("Limit reached but all messages are critical/non-dismissable. Bypassing limit.")
      }
    }
  }

  /// Removes a message by its UUID
  /// - Parameter id: The UUID of the message to remove
  public func removeMessage(id: UUID) {
    let initialCount = messages.count
    messages.removeAll { $0.id == id }
    if messages.count < initialCount {
      Logger.messaging.info("Removed message with id: \(id, privacy: .public)")
    } else {
      Logger.messaging.debug("Failed to remove message, id not found: \(id, privacy: .public)")
    }
  }

  /// Clears all messages of a specific category
  /// - Parameter category: The category to clear
  public func clear(category: AppMessageCategory) {
    let initialCount = messages.count
    messages.removeAll { msg in
      if msg.category == category {
        return true
      }
      return false
    }
    let removedCount = initialCount - messages.count
    Logger.messaging.info("Cleared \(removedCount) messages of category: \(category.rawValue, privacy: .public)")
  }
}
