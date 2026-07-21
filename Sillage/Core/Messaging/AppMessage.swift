//
//  AppMessage.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Category of the message
public enum AppMessageCategory: String, Sendable, Equatable {
  case navigation
  case track
  case system
  case network
  case weather
  case anchor
  case geoGarage
}

/// Severity of the message
public enum AppMessageSeverity: Int, Sendable, Equatable, Comparable {
  case info = 0
  case warning = 1
  case error = 2
  
  public static func < (lhs: AppMessageSeverity, rhs: AppMessageSeverity) -> Bool {
    return lhs.rawValue < rhs.rawValue
  }
}

/// Target destination for Settings
public enum SettingsTarget: Sendable, Equatable {
  case geoGarage
  case storage
  case trackManagement
}

/// Action to be executed
public enum AppMessageIntent: Sendable, Equatable {
  case none
  case openSettings(target: SettingsTarget)
}

/// Domain model representing an internal system message
public struct AppMessage: Identifiable, Sendable, Equatable {
  public let id: UUID
  public let title: LocalizedStringResource
  public let detail: LocalizedStringResource
  public let severity: AppMessageSeverity
  public let category: AppMessageCategory
  public let intent: AppMessageIntent
  public let isDismissable: Bool
  public let timestamp: Date

  public init(
    id: UUID = UUID(),
    title: LocalizedStringResource,
    detail: LocalizedStringResource,
    severity: AppMessageSeverity,
    category: AppMessageCategory,
    intent: AppMessageIntent = .none,
    isDismissable: Bool = true,
    timestamp: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.severity = severity
    self.category = category
    self.intent = intent
    self.isDismissable = isDismissable
    self.timestamp = timestamp
  }
}
