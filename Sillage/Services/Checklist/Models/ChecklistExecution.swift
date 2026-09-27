//
//  ChecklistExecution.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Represents the execution state of an active or past checklist session.
public enum ChecklistExecutionStatus: String, Codable, Sendable {
  case inProgress = "in_progress"
  case completed = "completed"
  case abandoned = "abandoned"
}

/// Represents an item snapshot within a specific checklist execution session.
public struct ChecklistExecutionItem: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let executionId: UUID
  public let sourceTemplateItemId: UUID?
  public let sortOrder: Int
  public let title: String
  public let detail: String?
  public let isMandatory: Bool
  public let isChecked: Bool
  public let checkedAt: Date?
  public let coordinate: CLLocationCoordinate2D?

  nonisolated public init(
    id: UUID = UUID(),
    executionId: UUID,
    sourceTemplateItemId: UUID?,
    sortOrder: Int,
    title: String,
    detail: String? = nil,
    isMandatory: Bool = false,
    isChecked: Bool = false,
    checkedAt: Date? = nil,
    coordinate: CLLocationCoordinate2D? = nil
  ) {
    self.id = id
    self.executionId = executionId
    self.sourceTemplateItemId = sourceTemplateItemId
    self.sortOrder = sortOrder
    self.title = title
    self.detail = detail
    self.isMandatory = isMandatory
    self.isChecked = isChecked
    self.checkedAt = checkedAt
    self.coordinate = coordinate
  }
}

/// Represents an active or completed checklist execution session.
public struct ChecklistExecution: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let templateId: UUID
  public let templateTitleSnapshot: String
  public let status: ChecklistExecutionStatus
  public let startedAt: Date
  public let completedAt: Date?
  public let notes: String?
  public let items: [ChecklistExecutionItem]

  nonisolated public init(
    id: UUID = UUID(),
    templateId: UUID,
    templateTitleSnapshot: String,
    status: ChecklistExecutionStatus = .inProgress,
    startedAt: Date = Date(),
    completedAt: Date? = nil,
    notes: String? = nil,
    items: [ChecklistExecutionItem] = []
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

  public var isAllMandatorySatisfied: Bool {
    items.filter(\.isMandatory).allSatisfy(\.isChecked)
  }

  public var isFullyCompleted: Bool {
    !items.isEmpty && items.allSatisfy(\.isChecked)
  }
}
