//
//  ChecklistSession.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Represents the status of an active or past checklist session.
public enum ChecklistSessionStatus: String, Codable, Sendable {
  case inProgress = "in_progress"
  case completed = "completed"
  case abandoned = "abandoned"
}

/// Represents an item snapshot within a specific checklist session.
public struct ChecklistSessionItem: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let sessionId: UUID
  public let sourceTemplateItemId: UUID?
  public let sortOrder: Int
  public let title: String
  public let detail: String?
  public let isChecked: Bool
  public let checkedAt: Date?
  public let coordinate: CLLocationCoordinate2D?

  nonisolated public init(
    id: UUID = UUID(),
    sessionId: UUID,
    sourceTemplateItemId: UUID?,
    sortOrder: Int,
    title: String,
    detail: String? = nil,
    isChecked: Bool = false,
    checkedAt: Date? = nil,
    coordinate: CLLocationCoordinate2D? = nil
  ) {
    self.id = id
    self.sessionId = sessionId
    self.sourceTemplateItemId = sourceTemplateItemId
    self.sortOrder = sortOrder
    self.title = title
    self.detail = detail
    self.isChecked = isChecked
    self.checkedAt = checkedAt
    self.coordinate = coordinate
  }
}

/// Represents an active or completed checklist session.
public struct ChecklistSession: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let templateId: UUID
  public let templateTitleSnapshot: String
  public let status: ChecklistSessionStatus
  public let startedAt: Date
  public let completedAt: Date?
  public let notes: String?
  public let items: [ChecklistSessionItem]

  nonisolated public init(
    id: UUID = UUID(),
    templateId: UUID,
    templateTitleSnapshot: String,
    status: ChecklistSessionStatus = .inProgress,
    startedAt: Date = Date(),
    completedAt: Date? = nil,
    notes: String? = nil,
    items: [ChecklistSessionItem] = []
  ) {
    self.id = id
    self.templateId = templateId
    self.templateTitleSnapshot = templateTitleSnapshot
    self.status = status
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.notes = notes
    self.items = items
  }

  // MARK: - Computed Business Metrics

  public var totalCount: Int { items.count }

  public var completedCount: Int { items.filter(\.isChecked).count }

  public var progressRatio: Double {
    guard !items.isEmpty else { return 0.0 }
    return Double(completedCount) / Double(totalCount)
  }

  public var isFullyCompleted: Bool {
    !items.isEmpty && items.allSatisfy(\.isChecked)
  }
}
