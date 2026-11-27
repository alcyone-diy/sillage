//
//  ChecklistCategoryItem.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Domain representation of a checklist category definition.
public struct ChecklistCategoryItem: Identifiable, Hashable, Sendable {
  public let id: String
  public let name: String
  public let icon: String?
  public let sortOrder: Int
  public let createdAt: Date
  public let updatedAt: Date

  nonisolated public init(
    id: String,
    name: String,
    icon: String? = nil,
    sortOrder: Int = 0,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.icon = icon
    self.sortOrder = sortOrder
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  /// Convenience title matching name.
  public var title: String { name }

  /// Convenience systemImage matching icon.
  public var systemImage: String? { icon }
}
