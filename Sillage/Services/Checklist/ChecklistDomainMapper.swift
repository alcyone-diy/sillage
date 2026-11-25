//
//  ChecklistDomainMapper.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import GRDB

/// Stateless pure mapper converting GRDB persistence records into Checklist domain models.
/// Declared `nonisolated` with zero state and zero dummy fallbacks so closures running on
/// SQLite reader/writer queues never capture service instances.
public enum ChecklistDomainMapper {
  nonisolated public static func parseUUID(_ string: String, fieldName: String) throws(ChecklistError) -> UUID {
    guard let uuid = UUID(uuidString: string) else {
      throw ChecklistError.databaseInconsistency("Invalid UUID for field '\(fieldName)': '\(string)'")
    }
    return uuid
  }

  nonisolated public static func parseStatus(_ rawValue: String) throws(ChecklistError) -> ChecklistSessionStatus {
    guard let status = ChecklistSessionStatus(rawValue: rawValue) else {
      throw ChecklistError.databaseInconsistency("Unknown session status: '\(rawValue)'")
    }
    return status
  }

  nonisolated public static func fetchCategoryInfo(for templateId: String, in db: Database) throws -> String {
    guard let record = try ChecklistTemplateRecord.fetchOne(db, key: templateId) else {
      throw ChecklistError.databaseInconsistency(
        "Missing parent template '\(templateId)' for checklist session"
      )
    }
    return record.category_id
  }

  nonisolated public static func resolveCategoryId(
    for templateId: String,
    in categoryIdByTemplateId: [String: String]
  ) throws(ChecklistError) -> String {
    guard let categoryId = categoryIdByTemplateId[templateId] else {
      throw ChecklistError.databaseInconsistency(
        "Missing parent template '\(templateId)' for checklist session"
      )
    }
    return categoryId
  }

  nonisolated public static func mapTemplate(
    record: ChecklistTemplateRecord,
    itemRecords: [ChecklistTemplateItemRecord]
  ) throws(ChecklistError) -> ChecklistTemplate {
    let templateId = try parseUUID(record.id, fieldName: "template.id")

    var domainItems: [ChecklistTemplateItem] = []
    domainItems.reserveCapacity(itemRecords.count)

    for itemRecord in itemRecords {
      domainItems.append(ChecklistTemplateItem(
        id: try parseUUID(itemRecord.id, fieldName: "template_item.id"),
        templateId: try parseUUID(itemRecord.template_id, fieldName: "template_item.template_id"),
        sortOrder: itemRecord.sort_order,
        title: itemRecord.title,
        detail: itemRecord.detail
      ))
    }

    return ChecklistTemplate(
      id: templateId,
      title: record.title,
      description: record.description,
      categoryId: record.category_id,
      sortOrder: record.sort_order,
      createdAt: record.created_at,
      updatedAt: record.updated_at,
      items: domainItems
    )
  }

  nonisolated public static func mapCategory(record: ChecklistCategoryRecord) -> ChecklistCategoryItem {
    ChecklistCategoryItem(
      id: record.id,
      name: record.name,
      icon: record.icon,
      sortOrder: record.sort_order,
      createdAt: record.created_at,
      updatedAt: record.updated_at
    )
  }

  nonisolated public static func mapSession(
    record: ChecklistSessionRecord,
    itemRecords: [ChecklistSessionItemRecord],
    categoryId: String
  ) throws(ChecklistError) -> ChecklistSession {
    let sessionId = try parseUUID(record.id, fieldName: "session.id")
    let templateId = try parseUUID(record.template_id, fieldName: "session.template_id")
    let status = try parseStatus(record.status)

    var domainItems: [ChecklistSessionItem] = []
    domainItems.reserveCapacity(itemRecords.count)

    for itemRecord in itemRecords {
      let itemId = try parseUUID(itemRecord.id, fieldName: "item.id")
      let sourceTemplateItemId: UUID?
      if let src = itemRecord.source_template_item_id {
        sourceTemplateItemId = try parseUUID(src, fieldName: "item.source_template_item_id")
      } else {
        sourceTemplateItemId = nil
      }

      let coordinate: CLLocationCoordinate2D?
      switch (itemRecord.latitude_deg, itemRecord.longitude_deg) {
      case let (lat?, lon?):
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
      case (nil, nil):
        coordinate = nil
      default:
        throw ChecklistError.databaseInconsistency(
          "Spatial atomicity violated on checklist item '\(itemRecord.id)'"
        )
      }

      domainItems.append(ChecklistSessionItem(
        id: itemId,
        sessionId: sessionId,
        sourceTemplateItemId: sourceTemplateItemId,
        sortOrder: itemRecord.sort_order,
        title: itemRecord.title,
        detail: itemRecord.detail,
        isChecked: itemRecord.is_checked,
        checkedAt: itemRecord.checked_at,
        coordinate: coordinate
      ))
    }

    return ChecklistSession(
      id: sessionId,
      templateId: templateId,
      templateTitleSnapshot: record.template_title_snapshot,
      categoryId: categoryId,
      status: status,
      startedAt: record.started_at,
      completedAt: record.completed_at,
      notes: record.notes,
      items: domainItems
    )
  }
}
