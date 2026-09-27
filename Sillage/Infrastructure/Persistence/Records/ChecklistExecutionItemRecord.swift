//
//  ChecklistExecutionItemRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence record for an item in a checklist execution session.
public struct ChecklistExecutionItemRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "checklist_execution_item"

  public var id: String
  public var execution_id: String
  public var source_template_item_id: String?
  public var sort_order: Int
  public var title: String
  public var detail: String?
  public var is_mandatory: Bool
  public var is_checked: Bool
  public var checked_at: Date?
  public var latitude_deg: Double?
  public var longitude_deg: Double?

  public init(
    id: String,
    execution_id: String,
    source_template_item_id: String? = nil,
    sort_order: Int,
    title: String,
    detail: String? = nil,
    is_mandatory: Bool = false,
    is_checked: Bool = false,
    checked_at: Date? = nil,
    latitude_deg: Double? = nil,
    longitude_deg: Double? = nil
  ) {
    self.id = id
    self.execution_id = execution_id
    self.source_template_item_id = source_template_item_id
    self.sort_order = sort_order
    self.title = title
    self.detail = detail
    self.is_mandatory = is_mandatory
    self.is_checked = is_checked
    self.checked_at = checked_at
    self.latitude_deg = latitude_deg
    self.longitude_deg = longitude_deg
  }

  public enum Columns: String, ColumnExpression {
    case id
    case execution_id
    case source_template_item_id
    case sort_order
    case title
    case detail
    case is_mandatory
    case is_checked
    case checked_at
    case latitude_deg
    case longitude_deg
  }

  public static let execution = belongsTo(ChecklistExecutionRecord.self)
}
