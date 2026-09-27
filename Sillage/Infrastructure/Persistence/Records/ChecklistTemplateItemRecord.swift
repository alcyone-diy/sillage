//
//  ChecklistTemplateItemRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence record for a checklist template item.
public struct ChecklistTemplateItemRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "checklist_template_item"

  public var id: String
  public var template_id: String
  public var sort_order: Int
  public var title: String
  public var detail: String?

  public init(
    id: String,
    template_id: String,
    sort_order: Int,
    title: String,
    detail: String? = nil
  ) {
    self.id = id
    self.template_id = template_id
    self.sort_order = sort_order
    self.title = title
    self.detail = detail
  }

  public enum Columns: String, ColumnExpression {
    case id
    case template_id
    case sort_order
    case title
    case detail
  }

  public static let template = belongsTo(ChecklistTemplateRecord.self)
}
