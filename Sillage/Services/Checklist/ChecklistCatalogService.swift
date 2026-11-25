//
//  ChecklistCatalogService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB
import OSLog

/// Stateless service managing nautical checklist templates, categories, and default seeding.
@MainActor
public struct ChecklistCatalogService: ChecklistCatalogServiceProtocol, Sendable {
  private let databaseManager: DatabaseManager

  public init(databaseManager: DatabaseManager) {
    self.databaseManager = databaseManager
  }

  // MARK: - Template Operations

  public func fetchTemplates() async throws -> [ChecklistTemplate] {
    try await databaseManager.reader.read { db in
      let templateRecords = try ChecklistTemplateRecord
        .order(ChecklistTemplateRecord.Columns.sort_order.asc)
        .fetchAll(db)

      return try templateRecords.map { tRecord in
        let items = try ChecklistTemplateItemRecord
          .filter(ChecklistTemplateItemRecord.Columns.template_id == tRecord.id)
          .order(ChecklistTemplateItemRecord.Columns.sort_order.asc)
          .fetchAll(db)
        return try ChecklistDomainMapper.mapTemplate(record: tRecord, itemRecords: items)
      }
    }
  }

  public func fetchTemplate(id: UUID) async throws -> ChecklistTemplate? {
    try await databaseManager.reader.read { db in
      guard let tRecord = try ChecklistTemplateRecord.fetchOne(db, key: id.uuidString) else {
        return nil
      }

      let items = try ChecklistTemplateItemRecord
        .filter(ChecklistTemplateItemRecord.Columns.template_id == tRecord.id)
        .order(ChecklistTemplateItemRecord.Columns.sort_order.asc)
        .fetchAll(db)

      return try ChecklistDomainMapper.mapTemplate(record: tRecord, itemRecords: items)
    }
  }

  public func createTemplate(
    title: String,
    description: String? = nil,
    categoryId: String = "routine",
    items: [(title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await databaseManager.write { db in
      let templateId = UUID()
      let now = Date()

      guard try ChecklistCategoryRecord.fetchOne(db, key: categoryId) != nil else {
        throw ChecklistError.categoryNotFound(categoryId)
      }

      let templateRecord = ChecklistTemplateRecord(
        id: templateId.uuidString,
        title: title,
        description: description,
        category_id: categoryId,
        sort_order: 0,
        created_at: now,
        updated_at: now
      )
      try templateRecord.insert(db)

      var domainItems: [ChecklistTemplateItem] = []
      domainItems.reserveCapacity(items.count)

      for (index, itemData) in items.enumerated() {
        let itemId = UUID()
        let itemRecord = ChecklistTemplateItemRecord(
          id: itemId.uuidString,
          template_id: templateId.uuidString,
          sort_order: index,
          title: itemData.title,
          detail: itemData.detail
        )
        try itemRecord.insert(db)

        domainItems.append(ChecklistTemplateItem(
          id: itemId,
          templateId: templateId,
          sortOrder: index,
          title: itemData.title,
          detail: itemData.detail
        ))
      }

      return ChecklistTemplate(
        id: templateId,
        title: title,
        description: description,
        categoryId: categoryId,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
        items: domainItems
      )
    }
  }

  public func updateTemplate(
    id: UUID,
    title: String,
    description: String? = nil,
    categoryId: String = "routine",
    items: [(id: UUID?, title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await databaseManager.write { db in
      guard let templateRecord = try ChecklistTemplateRecord.fetchOne(db, key: id.uuidString) else {
        throw ChecklistError.templateNotFound(id)
      }

      guard try ChecklistCategoryRecord.fetchOne(db, key: categoryId) != nil else {
        throw ChecklistError.categoryNotFound(categoryId)
      }

      let now = Date()
      var updatedTemplateRecord = templateRecord
      updatedTemplateRecord.title = title
      updatedTemplateRecord.description = description
      updatedTemplateRecord.category_id = categoryId
      updatedTemplateRecord.updated_at = now
      try updatedTemplateRecord.update(db)

      // Replace template items for this template
      try ChecklistTemplateItemRecord
        .filter(ChecklistTemplateItemRecord.Columns.template_id == id.uuidString)
        .deleteAll(db)

      var domainItems: [ChecklistTemplateItem] = []
      domainItems.reserveCapacity(items.count)

      for (index, itemData) in items.enumerated() {
        let itemId = itemData.id ?? UUID()
        let itemRecord = ChecklistTemplateItemRecord(
          id: itemId.uuidString,
          template_id: id.uuidString,
          sort_order: index,
          title: itemData.title,
          detail: itemData.detail
        )
        try itemRecord.insert(db)

        domainItems.append(ChecklistTemplateItem(
          id: itemId,
          templateId: id,
          sortOrder: index,
          title: itemData.title,
          detail: itemData.detail
        ))
      }

      // Atomically reconcile any active `.inProgress` session inside the same SQLite transaction
      try ChecklistSessionReconciler.reconcileActiveSessionIfPresent(
        for: id,
        updatedTitle: title,
        updatedItems: domainItems,
        in: db
      )

      Logger.checklist.info("Successfully updated template '\(id.uuidString, privacy: .public)'")

      return ChecklistTemplate(
        id: id,
        title: title,
        description: description,
        categoryId: categoryId,
        sortOrder: templateRecord.sort_order,
        createdAt: templateRecord.created_at,
        updatedAt: now,
        items: domainItems
      )
    }
  }

  public func deleteTemplate(id: UUID) async throws {
    try await databaseManager.write { db in
      guard let template = try ChecklistTemplateRecord.fetchOne(db, key: id.uuidString) else {
        throw ChecklistError.templateNotFound(id)
      }

      try template.delete(db)
      Logger.checklist.info("Successfully deleted template '\(id.uuidString, privacy: .public)'")
    }
  }

  public func seedDefaultTemplatesIfNeeded() async throws {
    try await databaseManager.write { db in
      try ChecklistSeeder.seedDefaultTemplatesIfNeeded(in: db)
    }
  }

  // MARK: - Category Operations

  public func fetchCategories() async throws -> [ChecklistCategoryItem] {
    try await databaseManager.reader.read { db in
      let records = try ChecklistCategoryRecord
        .order(ChecklistCategoryRecord.Columns.sort_order.asc)
        .fetchAll(db)
      return records.map(ChecklistDomainMapper.mapCategory)
    }
  }

  public func fetchCategory(id: String) async throws -> ChecklistCategoryItem? {
    try await databaseManager.reader.read { db in
      guard let record = try ChecklistCategoryRecord.fetchOne(db, key: id) else {
        return nil
      }
      return ChecklistDomainMapper.mapCategory(record: record)
    }
  }

  public func createCategory(
    id: String? = nil,
    name: String,
    icon: String? = nil,
    sortOrder: Int? = nil
  ) async throws -> ChecklistCategoryItem {
    try await databaseManager.write { db in
      let categoryId = id ?? UUID().uuidString
      let now = Date()
      let order = try sortOrder ?? ChecklistCategoryRecord.fetchCount(db)
      let record = ChecklistCategoryRecord(
        id: categoryId,
        name: name,
        icon: icon,
        sort_order: order,
        created_at: now,
        updated_at: now
      )
      try record.insert(db)
      Logger.checklist.info("Successfully created category '\(categoryId, privacy: .public)'")
      return ChecklistDomainMapper.mapCategory(record: record)
    }
  }

  public func updateCategory(
    id: String,
    name: String,
    icon: String? = nil,
    sortOrder: Int? = nil
  ) async throws -> ChecklistCategoryItem {
    try await databaseManager.write { db in
      guard let existing = try ChecklistCategoryRecord.fetchOne(db, key: id) else {
        throw ChecklistError.categoryNotFound(id)
      }
      let now = Date()
      var updated = existing
      updated.name = name
      updated.icon = icon
      if let sortOrder {
        updated.sort_order = sortOrder
      }
      updated.updated_at = now
      try updated.update(db)
      Logger.checklist.info("Successfully updated category '\(id, privacy: .public)'")
      return ChecklistDomainMapper.mapCategory(record: updated)
    }
  }

  public func deleteCategory(id: String) async throws {
    try await databaseManager.write { db in
      guard let category = try ChecklistCategoryRecord.fetchOne(db, key: id) else {
        throw ChecklistError.categoryNotFound(id)
      }
      let associatedCount = try ChecklistTemplateRecord
        .filter(ChecklistTemplateRecord.Columns.category_id == id)
        .fetchCount(db)
      guard associatedCount == 0 else {
        throw ChecklistError.categoryHasAssociatedTemplates(id)
      }
      try category.delete(db)
      Logger.checklist.info("Successfully deleted category '\(id, privacy: .public)'")
    }
  }

  public func reorderCategories(ids: [String]) async throws {
    try await databaseManager.write { db in
      let now = Date()
      for (index, id) in ids.enumerated() {
        guard var category = try ChecklistCategoryRecord.fetchOne(db, key: id) else {
          throw ChecklistError.categoryNotFound(id)
        }
        if category.sort_order != index {
          category.sort_order = index
          category.updated_at = now
          try category.update(db)
        }
      }
      Logger.checklist.info("Successfully reordered \(ids.count, privacy: .public) categories")
    }
  }

  public func fetchChecklistCountsByCategory() async throws -> [String: Int] {
    try await databaseManager.reader.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT \(ChecklistTemplateRecord.Columns.category_id.name), COUNT(*)
        FROM \(ChecklistTemplateRecord.databaseTableName)
        GROUP BY \(ChecklistTemplateRecord.Columns.category_id.name)
        """
      )
      var counts: [String: Int] = [:]
      for row in rows {
        if let categoryId: String = row[0], let count: Int = row[1] {
          counts[categoryId] = count
        }
      }
      return counts
    }
  }
}
