//
//  ChecklistTemplate.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Represents a single reusable step within a checklist template.
public struct ChecklistTemplateItem: Identifiable, Hashable, Sendable {
  public let id: UUID
  public let templateId: UUID
  public let sortOrder: Int
  public let title: String
  public let detail: String?

  nonisolated public init(
    id: UUID = UUID(),
    templateId: UUID,
    sortOrder: Int,
    title: String,
    detail: String? = nil
  ) {
    self.id = id
    self.templateId = templateId
    self.sortOrder = sortOrder
    self.title = title
    self.detail = detail
  }
}

/// Represents a reusable maritime checklist template definition.
public struct ChecklistTemplate: Identifiable, Hashable, Sendable {
  public let id: UUID
  public let title: String
  public let description: String?
  public let category: ChecklistCategory
  public let categoryId: String
  public let sortOrder: Int
  public let createdAt: Date
  public let updatedAt: Date
  public let items: [ChecklistTemplateItem]

  nonisolated public init(
    id: UUID = UUID(),
    title: String,
    description: String? = nil,
    category: ChecklistCategory,
    categoryId: String? = nil,
    sortOrder: Int = 0,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    items: [ChecklistTemplateItem] = []
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.category = category
    self.categoryId = categoryId ?? category.rawValue
    self.sortOrder = sortOrder
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.items = items
  }
}
