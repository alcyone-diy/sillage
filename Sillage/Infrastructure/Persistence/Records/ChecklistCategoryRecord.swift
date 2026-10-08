//
//  ChecklistCategoryRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence record for a checklist category.
public struct ChecklistCategoryRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable {
  public static let databaseTableName = "checklist_category"

  public var id: String
  public var name: String
  public var icon: String?
  public var sort_order: Int
  public var created_at: Date
  public var updated_at: Date

  public init(
    id: String,
    name: String,
    icon: String? = nil,
    sort_order: Int = 0,
    created_at: Date = Date(),
    updated_at: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.icon = icon
    self.sort_order = sort_order
    self.created_at = created_at
    self.updated_at = updated_at
  }

  public enum Columns: String, ColumnExpression {
    case id
    case name
    case icon
    case sort_order
    case created_at
    case updated_at
  }

  public static let templates = hasMany(ChecklistTemplateRecord.self, using: ForeignKey(["category_id"]))
}
