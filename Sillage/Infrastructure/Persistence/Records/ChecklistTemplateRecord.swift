//
//  ChecklistTemplateRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence record for a checklist template.
public struct ChecklistTemplateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "checklist_template"

  public var id: String
  public var title: String
  public var description: String?
  public var category: String
  public var sort_order: Int
  public var created_at: Date
  public var updated_at: Date

  public init(
    id: String,
    title: String,
    description: String? = nil,
    category: String,
    sort_order: Int = 0,
    created_at: Date,
    updated_at: Date
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.category = category
    self.sort_order = sort_order
    self.created_at = created_at
    self.updated_at = updated_at
  }

  public enum Columns: String, ColumnExpression {
    case id
    case title
    case description
    case category
    case sort_order
    case created_at
    case updated_at
  }

  public static let items = hasMany(ChecklistTemplateItemRecord.self)
  public static let sessions = hasMany(ChecklistSessionRecord.self)
}
