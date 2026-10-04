//
//  ChecklistSessionItemRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence record for an item in a checklist session.
public struct ChecklistSessionItemRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "checklist_session_item"

  public var id: String
  public var session_id: String
  public var source_template_item_id: String?
  public var sort_order: Int
  public var title: String
  public var detail: String?
  public var is_checked: Bool
  public var checked_at: Date?
  public var latitude_deg: Double?
  public var longitude_deg: Double?

  public init(
    id: String,
    session_id: String,
    source_template_item_id: String? = nil,
    sort_order: Int,
    title: String,
    detail: String? = nil,
    is_checked: Bool = false,
    checked_at: Date? = nil,
    latitude_deg: Double? = nil,
    longitude_deg: Double? = nil
  ) {
    self.id = id
    self.session_id = session_id
    self.source_template_item_id = source_template_item_id
    self.sort_order = sort_order
    self.title = title
    self.detail = detail
    self.is_checked = is_checked
    self.checked_at = checked_at
    self.latitude_deg = latitude_deg
    self.longitude_deg = longitude_deg
  }

  public enum Columns: String, ColumnExpression {
    case id
    case session_id
    case source_template_item_id
    case sort_order
    case title
    case detail
    case is_checked
    case checked_at
    case latitude_deg
    case longitude_deg
  }

  public static let session = belongsTo(ChecklistSessionRecord.self, using: ForeignKey(["session_id"]))
}
