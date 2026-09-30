//
//  ChecklistSessionRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence record for a checklist session.
public struct ChecklistSessionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "checklist_session"

  public var id: String
  public var template_id: String
  public var template_title_snapshot: String
  public var status: String
  public var started_at: Date
  public var completed_at: Date?
  public var notes: String?

  public init(
    id: String,
    template_id: String,
    template_title_snapshot: String,
    status: String,
    started_at: Date,
    completed_at: Date? = nil,
    notes: String? = nil
  ) {
    self.id = id
    self.template_id = template_id
    self.template_title_snapshot = template_title_snapshot
    self.status = status
    self.started_at = started_at
    self.completed_at = completed_at
    self.notes = notes
  }

  public enum Columns: String, ColumnExpression {
    case id
    case template_id
    case template_title_snapshot
    case status
    case started_at
    case completed_at
    case notes
  }

  public static let items = hasMany(ChecklistSessionItemRecord.self)
  public static let template = belongsTo(ChecklistTemplateRecord.self)
}
