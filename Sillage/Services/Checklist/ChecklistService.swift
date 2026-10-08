//
//  ChecklistService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB
import OSLog
import CoreLocation

/// Thread-safe service managing nautical checklist templates and session lifecycles.
public final class ChecklistService: ChecklistServiceProtocol {
  private let databaseManager: DatabaseManager
  private let throttler: ChecklistThrottler

  public init(databaseManager: DatabaseManager, throttler: ChecklistThrottler = ChecklistThrottler()) {
    self.databaseManager = databaseManager
    self.throttler = throttler
  }

  // MARK: - Static Pure Mappings (Zero Self-Capture, Zero Dummy Values)

  nonisolated private static func parseUUID(_ string: String, fieldName: String) throws(ChecklistSessionError) -> UUID {
    guard let uuid = UUID(uuidString: string) else {
      throw ChecklistSessionError.databaseInconsistency("Invalid UUID for field '\(fieldName)': '\(string)'")
    }
    return uuid
  }

  nonisolated private static func parseStatus(_ rawValue: String) throws(ChecklistSessionError) -> ChecklistSessionStatus {
    guard let status = ChecklistSessionStatus(rawValue: rawValue) else {
      throw ChecklistSessionError.databaseInconsistency("Unknown session status: '\(rawValue)'")
    }
    return status
  }

  nonisolated private static func fetchCategoryInfo(for templateId: String, in db: Database) throws -> (category: ChecklistCategory, categoryId: String) {
    guard let record = try ChecklistTemplateRecord.fetchOne(db, key: templateId) else {
      return (.routine, ChecklistCategory.routine.rawValue)
    }
    let category = ChecklistCategory(rawValue: record.category) ?? ChecklistCategory(rawValue: record.category_id) ?? .routine
    return (category, record.category_id)
  }

  nonisolated public static func mapSession(
    record: ChecklistSessionRecord,
    itemRecords: [ChecklistSessionItemRecord],
    category: ChecklistCategory = .routine,
    categoryId: String? = nil
  ) throws(ChecklistSessionError) -> ChecklistSession {
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
        throw ChecklistSessionError.databaseInconsistency(
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
      category: category,
      categoryId: categoryId ?? category.rawValue,
      status: status,
      startedAt: record.started_at,
      completedAt: record.completed_at,
      notes: record.notes,
      items: domainItems
    )
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

        guard let category = ChecklistCategory(rawValue: tRecord.category) ?? ChecklistCategory(rawValue: tRecord.category_id) else {
          throw ChecklistSessionError.databaseInconsistency("Unknown checklist category: \(tRecord.category)")
        }

        let domainItems = try items.map { iRecord in
          ChecklistTemplateItem(
            id: try Self.parseUUID(iRecord.id, fieldName: "template_item.id"),
            templateId: try Self.parseUUID(iRecord.template_id, fieldName: "template_item.template_id"),
            sortOrder: iRecord.sort_order,
            title: iRecord.title,
            detail: iRecord.detail
          )
        }

        return ChecklistTemplate(
          id: try Self.parseUUID(tRecord.id, fieldName: "template.id"),
          title: tRecord.title,
          description: tRecord.description,
          category: category,
          categoryId: tRecord.category_id,
          sortOrder: tRecord.sort_order,
          createdAt: tRecord.created_at,
          updatedAt: tRecord.updated_at,
          items: domainItems
        )
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

      guard let category = ChecklistCategory(rawValue: tRecord.category) ?? ChecklistCategory(rawValue: tRecord.category_id) else {
        throw ChecklistSessionError.databaseInconsistency("Unknown checklist category: \(tRecord.category)")
      }

      let domainItems = try items.map { iRecord in
        ChecklistTemplateItem(
          id: try Self.parseUUID(iRecord.id, fieldName: "template_item.id"),
          templateId: try Self.parseUUID(iRecord.template_id, fieldName: "template_item.template_id"),
          sortOrder: iRecord.sort_order,
          title: iRecord.title,
          detail: iRecord.detail
        )
      }

      return ChecklistTemplate(
        id: try Self.parseUUID(tRecord.id, fieldName: "template.id"),
        title: tRecord.title,
        description: tRecord.description,
        category: category,
        categoryId: tRecord.category_id,
        sortOrder: tRecord.sort_order,
        createdAt: tRecord.created_at,
        updatedAt: tRecord.updated_at,
        items: domainItems
      )
    }
  }

  public func createTemplate(
    title: String,
    description: String? = nil,
    category: ChecklistCategory,
    items: [(title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await createTemplate(
      title: title,
      description: description,
      category: category,
      categoryId: nil,
      items: items
    )
  }

  public func createTemplate(
    title: String,
    description: String? = nil,
    category: ChecklistCategory,
    categoryId: String?,
    items: [(title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await databaseManager.write { db in
      let templateId = UUID()
      let now = Date()
      let resolvedCategoryId = categoryId ?? category.rawValue

      // Ensure category exists in checklist_category
      guard try ChecklistCategoryRecord.fetchOne(db, key: resolvedCategoryId) != nil else {
        throw ChecklistSessionError.categoryNotFound(resolvedCategoryId)
      }

      let templateRecord = ChecklistTemplateRecord(
        id: templateId.uuidString,
        title: title,
        description: description,
        category: category.rawValue,
        category_id: resolvedCategoryId,
        sort_order: 0,
        created_at: now,
        updated_at: now
      )
      try templateRecord.insert(db)

      var domainItems: [ChecklistTemplateItem] = []
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
        category: category,
        categoryId: resolvedCategoryId,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
        items: domainItems
      )
    }
  }

  public func createCustomTemplate(
    title: String,
    description: String? = nil,
    category: ChecklistCategory,
    items: [(title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await createTemplate(title: title, description: description, category: category, categoryId: nil, items: items)
  }

  public func createCustomTemplate(
    title: String,
    description: String? = nil,
    category: ChecklistCategory,
    categoryId: String?,
    items: [(title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await createTemplate(title: title, description: description, category: category, categoryId: categoryId, items: items)
  }

  public func updateTemplate(
    id: UUID,
    title: String,
    description: String? = nil,
    category: ChecklistCategory,
    items: [(id: UUID?, title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await updateTemplate(
      id: id,
      title: title,
      description: description,
      category: category,
      categoryId: nil,
      items: items
    )
  }

  public func updateTemplate(
    id: UUID,
    title: String,
    description: String? = nil,
    category: ChecklistCategory,
    categoryId: String?,
    items: [(id: UUID?, title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await databaseManager.write { db in
      guard let templateRecord = try ChecklistTemplateRecord.fetchOne(db, key: id.uuidString) else {
        throw ChecklistSessionError.templateNotFound(id)
      }

      let resolvedCategoryId = categoryId ?? category.rawValue
      guard try ChecklistCategoryRecord.fetchOne(db, key: resolvedCategoryId) != nil else {
        throw ChecklistSessionError.categoryNotFound(resolvedCategoryId)
      }

      let now = Date()
      var updatedTemplateRecord = templateRecord
      updatedTemplateRecord.title = title
      updatedTemplateRecord.description = description
      updatedTemplateRecord.category = category.rawValue
      updatedTemplateRecord.category_id = resolvedCategoryId
      updatedTemplateRecord.updated_at = now
      try updatedTemplateRecord.update(db)

      // Replace template items for this template
      try ChecklistTemplateItemRecord
        .filter(ChecklistTemplateItemRecord.Columns.template_id == id.uuidString)
        .deleteAll(db)

      var domainItems: [ChecklistTemplateItem] = []
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

      // Update active session snapshot and items if in progress
      if let activeSession = try ChecklistSessionRecord
        .filter(ChecklistSessionRecord.Columns.template_id == id.uuidString)
        .filter(ChecklistSessionRecord.Columns.status == ChecklistSessionStatus.inProgress.rawValue)
        .fetchOne(db) {
        var updatedSession = activeSession
        updatedSession.template_title_snapshot = title
        try updatedSession.update(db)

        let existingSessionItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == activeSession.id)
          .fetchAll(db)

        var existingBySourceId: [String: ChecklistSessionItemRecord] = [:]
        var existingByTitle: [String: ChecklistSessionItemRecord] = [:]
        for item in existingSessionItems {
          if let src = item.source_template_item_id {
            existingBySourceId[src] = item
          }
          existingByTitle[item.title] = item
        }

        try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == activeSession.id)
          .deleteAll(db)

        for (index, domainItem) in domainItems.enumerated() {
          let sourceId = domainItem.id.uuidString
          let prior = existingBySourceId[sourceId] ?? existingByTitle[domainItem.title]

          let sessionItemRecord = ChecklistSessionItemRecord(
            id: prior?.id ?? UUID().uuidString,
            session_id: activeSession.id,
            source_template_item_id: sourceId,
            sort_order: index,
            title: domainItem.title,
            detail: domainItem.detail,
            is_checked: prior?.is_checked ?? false,
            checked_at: prior?.checked_at,
            latitude_deg: prior?.latitude_deg,
            longitude_deg: prior?.longitude_deg
          )
          try sessionItemRecord.insert(db)
        }
      }

      Logger.checklist.info("Successfully updated template '\(id.uuidString, privacy: .public)'")

      return ChecklistTemplate(
        id: id,
        title: title,
        description: description,
        category: category,
        categoryId: resolvedCategoryId,
        sortOrder: templateRecord.sort_order,
        createdAt: templateRecord.created_at,
        updatedAt: now,
        items: domainItems
      )
    }
  }

  public func updateCustomTemplate(
    id: UUID,
    title: String,
    description: String? = nil,
    category: ChecklistCategory,
    items: [(id: UUID?, title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await updateTemplate(id: id, title: title, description: description, category: category, categoryId: nil, items: items)
  }

  public func updateCustomTemplate(
    id: UUID,
    title: String,
    description: String? = nil,
    category: ChecklistCategory,
    categoryId: String?,
    items: [(id: UUID?, title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await updateTemplate(id: id, title: title, description: description, category: category, categoryId: categoryId, items: items)
  }

  public func deleteTemplate(id: UUID) async throws {
    try await databaseManager.write { db in
      guard let template = try ChecklistTemplateRecord.fetchOne(db, key: id.uuidString) else {
        throw ChecklistSessionError.templateNotFound(id)
      }

      try template.delete(db)
      Logger.checklist.info("Successfully deleted template '\(id.uuidString, privacy: .public)'")
    }
  }

  public func deleteCustomTemplate(id: UUID) async throws {
    try await deleteTemplate(id: id)
  }

  // MARK: - Category Operations

  public func fetchCategories() async throws -> [ChecklistCategoryItem] {
    try await databaseManager.reader.read { db in
      let records = try ChecklistCategoryRecord
        .order(ChecklistCategoryRecord.Columns.sort_order.asc)
        .fetchAll(db)
      return records.map {
        ChecklistCategoryItem(
          id: $0.id,
          name: $0.name,
          icon: $0.icon,
          sortOrder: $0.sort_order,
          createdAt: $0.created_at,
          updatedAt: $0.updated_at
        )
      }
    }
  }

  public func fetchCategory(id: String) async throws -> ChecklistCategoryItem? {
    try await databaseManager.reader.read { db in
      guard let record = try ChecklistCategoryRecord.fetchOne(db, key: id) else {
        return nil
      }
      return ChecklistCategoryItem(
        id: record.id,
        name: record.name,
        icon: record.icon,
        sortOrder: record.sort_order,
        createdAt: record.created_at,
        updatedAt: record.updated_at
      )
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
      return ChecklistCategoryItem(
        id: categoryId,
        name: name,
        icon: icon,
        sortOrder: order,
        createdAt: now,
        updatedAt: now
      )
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
        throw ChecklistSessionError.categoryNotFound(id)
      }
      let now = Date()
      var updated = existing
      updated.name = name
      updated.icon = icon
      if let sortOrder = sortOrder {
        updated.sort_order = sortOrder
      }
      updated.updated_at = now
      try updated.update(db)
      Logger.checklist.info("Successfully updated category '\(id, privacy: .public)'")
      return ChecklistCategoryItem(
        id: updated.id,
        name: updated.name,
        icon: updated.icon,
        sortOrder: updated.sort_order,
        createdAt: updated.created_at,
        updatedAt: updated.updated_at
      )
    }
  }

  public func deleteCategory(id: String) async throws {
    try await databaseManager.write { db in
      guard let category = try ChecklistCategoryRecord.fetchOne(db, key: id) else {
        throw ChecklistSessionError.categoryNotFound(id)
      }
      let associatedCount = try ChecklistTemplateRecord
        .filter(ChecklistTemplateRecord.Columns.category_id == id || ChecklistTemplateRecord.Columns.category == id)
        .fetchCount(db)
      guard associatedCount == 0 else {
        throw ChecklistSessionError.categoryHasAssociatedTemplates(id)
      }
      try category.delete(db)
      Logger.checklist.info("Successfully deleted category '\(id, privacy: .public)'")
    }
  }

  // MARK: - Session Lifecycle (Get-or-Create)

  public func startSession(templateId: UUID) async throws(ChecklistSessionError) -> ChecklistSession {
    do {
      return try await databaseManager.write { db in
        // 1. Transparent Get-or-Create: Resume existing in-progress session if present
        let activeRecord = try ChecklistSessionRecord
          .filter(ChecklistSessionRecord.Columns.template_id == templateId.uuidString)
          .filter(ChecklistSessionRecord.Columns.status == ChecklistSessionStatus.inProgress.rawValue)
          .fetchOne(db)

        if let existingRecord = activeRecord {
          Logger.checklist.info(
            "Resuming existing active session for template '\(templateId.uuidString, privacy: .public)'"
          )
          let catInfo = try Self.fetchCategoryInfo(for: templateId.uuidString, in: db)
          let existingItems = try ChecklistSessionItemRecord
            .filter(ChecklistSessionItemRecord.Columns.session_id == existingRecord.id)
            .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
            .fetchAll(db)
          return try Self.mapSession(record: existingRecord, itemRecords: existingItems, category: catInfo.category, categoryId: catInfo.categoryId)
        }

        // 2. Normal path: Instantiate new session from template snapshot
        guard let templateRecord = try ChecklistTemplateRecord.fetchOne(db, key: templateId.uuidString) else {
          throw ChecklistSessionError.templateNotFound(templateId)
        }

        let templateItems = try ChecklistTemplateItemRecord
          .filter(ChecklistTemplateItemRecord.Columns.template_id == templateId.uuidString)
          .order(ChecklistTemplateItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        let sessionId = UUID()
        let now = Date()

        let sessionRecord = ChecklistSessionRecord(
          id: sessionId.uuidString,
          template_id: templateId.uuidString,
          template_title_snapshot: templateRecord.title,
          status: ChecklistSessionStatus.inProgress.rawValue,
          started_at: now,
          completed_at: nil,
          notes: nil
        )
        try sessionRecord.insert(db)

        var itemRecords: [ChecklistSessionItemRecord] = []
        for item in templateItems {
          let itemRecord = ChecklistSessionItemRecord(
            id: UUID().uuidString,
            session_id: sessionId.uuidString,
            source_template_item_id: item.id,
            sort_order: item.sort_order,
            title: item.title,
            detail: item.detail,
            is_checked: false,
            checked_at: nil,
            latitude_deg: nil,
            longitude_deg: nil
          )
          try itemRecord.insert(db)
          itemRecords.append(itemRecord)
        }

        let catInfo = (
          category: ChecklistCategory(rawValue: templateRecord.category) ?? ChecklistCategory(rawValue: templateRecord.category_id) ?? .routine,
          categoryId: templateRecord.category_id
        )
        Logger.checklist.info("Started new checklist session '\(sessionId.uuidString, privacy: .public)'")
        return try Self.mapSession(record: sessionRecord, itemRecords: itemRecords, category: catInfo.category, categoryId: catInfo.categoryId)
      }
    } catch let error as ChecklistSessionError {
      throw error
    } catch {
      Logger.checklist.error("Failed to start checklist session: \(error, privacy: .public)")
      throw ChecklistSessionError.databaseFailure(error.localizedDescription)
    }
  }

  public func setItemChecked(
    sessionId: UUID,
    itemId: UUID,
    isChecked: Bool,
    coordinate: CLLocationCoordinate2D? = nil
  ) async throws(ChecklistSessionError) -> ChecklistSession {
    // 1. Debounce rapid vibrations / wet touch screen taps
    guard await throttler.shouldProcessAction(for: itemId) else {
      Logger.checklist.debug("Debouncing action on item '\(itemId, privacy: .public)'")
      do {
        guard let current = try await fetchSession(id: sessionId) else {
          throw ChecklistSessionError.sessionNotFound(sessionId)
        }
        return current
      } catch let error as ChecklistSessionError {
        throw error
      } catch {
        throw ChecklistSessionError.databaseFailure(error.localizedDescription)
      }
    }

    do {
      return try await databaseManager.write { db in
        guard let sessionRecord = try ChecklistSessionRecord.fetchOne(db, key: sessionId.uuidString) else {
          throw ChecklistSessionError.sessionNotFound(sessionId)
        }
        guard sessionRecord.status == ChecklistSessionStatus.inProgress.rawValue else {
          throw ChecklistSessionError.sessionAlreadyFinished(sessionId)
        }
        guard var itemRecord = try ChecklistSessionItemRecord.fetchOne(db, key: itemId.uuidString) else {
          throw ChecklistSessionError.itemNotFound(itemId)
        }

        // 2. Strict Idempotency: Return immediately with 0 disk write if state is identical
        if itemRecord.is_checked == isChecked {
          let allItems = try ChecklistSessionItemRecord
            .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
            .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
            .fetchAll(db)
          let catInfo = try Self.fetchCategoryInfo(for: sessionRecord.template_id, in: db)
          return try Self.mapSession(record: sessionRecord, itemRecords: allItems, category: catInfo.category, categoryId: catInfo.categoryId)
        }

        // Count previously checked items before updating this item
        let previouslyCheckedCount = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
          .filter(ChecklistSessionItemRecord.Columns.is_checked == true)
          .fetchCount(db)

        itemRecord.is_checked = isChecked
        itemRecord.checked_at = isChecked ? Date() : nil
        itemRecord.latitude_deg = isChecked ? coordinate?.latitude : nil
        itemRecord.longitude_deg = isChecked ? coordinate?.longitude : nil
        try itemRecord.update(db)

        // When checking the first item, update started_at to now.
        var updatedSessionRecord = sessionRecord
        if isChecked && previouslyCheckedCount == 0 {
          let now = Date()
          updatedSessionRecord.started_at = now
          try updatedSessionRecord.update(db)
        }

        let allItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        let catInfo = try Self.fetchCategoryInfo(for: sessionRecord.template_id, in: db)
        return try Self.mapSession(record: updatedSessionRecord, itemRecords: allItems, category: catInfo.category, categoryId: catInfo.categoryId)
      }
    } catch let error as ChecklistSessionError {
      throw error
    } catch {
      throw ChecklistSessionError.databaseFailure(error.localizedDescription)
    }
  }

  public func completeSession(
    sessionId: UUID,
    notes: String? = nil
  ) async throws(ChecklistSessionError) -> ChecklistSession {
    do {
      return try await databaseManager.write { db in
        guard var sessionRecord = try ChecklistSessionRecord.fetchOne(db, key: sessionId.uuidString) else {
          throw ChecklistSessionError.sessionNotFound(sessionId)
        }
        guard sessionRecord.status == ChecklistSessionStatus.inProgress.rawValue else {
          throw ChecklistSessionError.sessionAlreadyFinished(sessionId)
        }

        let allItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        sessionRecord.status = ChecklistSessionStatus.completed.rawValue
        sessionRecord.completed_at = Date()
        sessionRecord.notes = notes
        try sessionRecord.update(db)

        let catInfo = try Self.fetchCategoryInfo(for: sessionRecord.template_id, in: db)
        Logger.checklist.info("Completed checklist session '\(sessionId.uuidString, privacy: .public)'")
        return try Self.mapSession(record: sessionRecord, itemRecords: allItems, category: catInfo.category, categoryId: catInfo.categoryId)
      }
    } catch let error as ChecklistSessionError {
      throw error
    } catch {
      throw ChecklistSessionError.databaseFailure(error.localizedDescription)
    }
  }

  public func deleteSession(sessionId: UUID) async throws(ChecklistSessionError) {
    do {
      try await databaseManager.write { db in
        guard let sessionRecord = try ChecklistSessionRecord.fetchOne(db, key: sessionId.uuidString) else {
          throw ChecklistSessionError.sessionNotFound(sessionId)
        }

        try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
          .deleteAll(db)

        try sessionRecord.delete(db)

        Logger.checklist.info("Deleted checklist session '\(sessionId.uuidString, privacy: .public)'")
      }
    } catch let error as ChecklistSessionError {
      throw error
    } catch {
      throw ChecklistSessionError.databaseFailure(error.localizedDescription)
    }
  }

  public func abandonSession(sessionId: UUID) async throws(ChecklistSessionError) -> ChecklistSession {
    do {
      return try await databaseManager.write { db in
        guard var sessionRecord = try ChecklistSessionRecord.fetchOne(db, key: sessionId.uuidString) else {
          throw ChecklistSessionError.sessionNotFound(sessionId)
        }
        guard sessionRecord.status == ChecklistSessionStatus.inProgress.rawValue else {
          throw ChecklistSessionError.sessionAlreadyFinished(sessionId)
        }

        sessionRecord.status = ChecklistSessionStatus.abandoned.rawValue
        sessionRecord.completed_at = Date()
        try sessionRecord.update(db)

        let allItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        let catInfo = try Self.fetchCategoryInfo(for: sessionRecord.template_id, in: db)
        Logger.checklist.info("Abandoned checklist session '\(sessionId.uuidString, privacy: .public)'")
        return try Self.mapSession(record: sessionRecord, itemRecords: allItems, category: catInfo.category, categoryId: catInfo.categoryId)
      }
    } catch let error as ChecklistSessionError {
      throw error
    } catch {
      throw ChecklistSessionError.databaseFailure(error.localizedDescription)
    }
  }

  public func fetchActiveSession(for templateId: UUID) async throws -> ChecklistSession? {
    try await databaseManager.reader.read { db in
      guard let record = try ChecklistSessionRecord
        .filter(ChecklistSessionRecord.Columns.template_id == templateId.uuidString)
        .filter(ChecklistSessionRecord.Columns.status == ChecklistSessionStatus.inProgress.rawValue)
        .fetchOne(db) else {
        return nil
      }

      let items = try ChecklistSessionItemRecord
        .filter(ChecklistSessionItemRecord.Columns.session_id == record.id)
        .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
        .fetchAll(db)

      let catInfo = try Self.fetchCategoryInfo(for: record.template_id, in: db)
      return try Self.mapSession(record: record, itemRecords: items, category: catInfo.category, categoryId: catInfo.categoryId)
    }
  }

  public func fetchSession(id: UUID) async throws -> ChecklistSession? {
    try await databaseManager.reader.read { db in
      guard let record = try ChecklistSessionRecord.fetchOne(db, key: id.uuidString) else {
        return nil
      }

      let items = try ChecklistSessionItemRecord
        .filter(ChecklistSessionItemRecord.Columns.session_id == record.id)
        .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
        .fetchAll(db)

      let catInfo = try Self.fetchCategoryInfo(for: record.template_id, in: db)
      return try Self.mapSession(record: record, itemRecords: items, category: catInfo.category, categoryId: catInfo.categoryId)
    }
  }

  public func fetchRecentSessions(limit: Int) async throws -> [ChecklistSession] {
    try await databaseManager.reader.read { db in
      let templates = try ChecklistTemplateRecord.fetchAll(db)
      let categoryInfoByTemplateId = Dictionary(uniqueKeysWithValues: templates.map { t in
        (t.id, (category: ChecklistCategory(rawValue: t.category) ?? ChecklistCategory(rawValue: t.category_id) ?? .routine, categoryId: t.category_id))
      })

      let records = try ChecklistSessionRecord
        .order(ChecklistSessionRecord.Columns.started_at.desc)
        .limit(limit)
        .fetchAll(db)

      return try records.map { record in
        let items = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == record.id)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)
        let info = categoryInfoByTemplateId[record.template_id] ?? (.routine, ChecklistCategory.routine.rawValue)
        return try Self.mapSession(record: record, itemRecords: items, category: info.category, categoryId: info.categoryId)
      }
    }
  }

  public func fetchLatestCompletionDate(for templateId: UUID) async throws -> Date? {
    try await databaseManager.reader.read { db in
      let row = try Row.fetchOne(
        db,
        sql: """
        SELECT MAX(completed_at) AS latest_completed_at
        FROM \(ChecklistSessionRecord.databaseTableName)
        WHERE template_id = ? AND status = ? AND completed_at IS NOT NULL
        """,
        arguments: [templateId.uuidString, ChecklistSessionStatus.completed.rawValue]
      )
      return row?["latest_completed_at"]
    }
  }

  public func seedDefaultTemplatesIfNeeded() async throws {
    try await databaseManager.write { db in
      try ChecklistSeeder.seedDefaultTemplatesIfNeeded(in: db)
    }
  }

  // MARK: - Reactive Observation (AsyncThrowingStream, No Task.detached)

  /// Retention duration in hours for recently completed sessions in active observation.
  public static let completedSessionRetentionHours: Int = 48

  /// Observes all active in-progress and recently completed checklist sessions in real-time.
  ///
  /// Architectural & UX Decisions:
  /// 1. **Frozen Retention Cutoff:** `thresholdDate` is computed ONCE outside the `ValueObservation.tracking` closure
  ///    using `completedSessionRetentionHours` (48 hours). This freezes the cutoff timestamp at observation start,
  ///    guaranteeing that a completed checklist never disappears under the mariner's eyes while they are actively reading or using the screen.
  /// 2. **Memory Protection & OOM Prevention:** Completed sessions older than 48 hours at the time of observation
  ///    start are excluded directly in SQLite, ensuring memory consumption stays constant over months of sailing.
  /// 3. **No Expiration for In-Progress:** Sessions with `.inProgress` status are never filtered by time; ongoing
  ///    nautical operations remain available until explicitly finished or restarted.
  /// 4. **Defensive Limit:** The `.limit(50)` clause prevents runaway memory allocations in extreme scenarios.
  public func observeSessions() -> AsyncThrowingStream<[ChecklistSession], any Error> {
    // 1. Calculate the threshold date FROZEN at the moment observation begins
    let thresholdDate = Date().addingTimeInterval(-Double(Self.completedSessionRetentionHours) * 3600)

    let observation = ValueObservation.tracking { db in
      let templates = try ChecklistTemplateRecord.fetchAll(db)
      let categoryInfoByTemplateId = Dictionary(uniqueKeysWithValues: templates.map { t in
        (t.id, (category: ChecklistCategory(rawValue: t.category) ?? ChecklistCategory(rawValue: t.category_id) ?? .routine, categoryId: t.category_id))
      })

      let statusCol = ChecklistSessionRecord.Columns.status
      let completedAtCol = ChecklistSessionRecord.Columns.completed_at

      let inProgress = statusCol == ChecklistSessionStatus.inProgress.rawValue
      let recentlyCompleted = statusCol == ChecklistSessionStatus.completed.rawValue && completedAtCol >= thresholdDate

      // 2. Typed query with a safety limit
      let records = try ChecklistSessionRecord
        .filter(inProgress || recentlyCompleted)
        .order(ChecklistSessionRecord.Columns.started_at.desc)
        .limit(50)
        .fetchAll(db)

      return try records.map { record in
        let items = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == record.id)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)
        let info = categoryInfoByTemplateId[record.template_id] ?? (.routine, ChecklistCategory.routine.rawValue)
        return try Self.mapSession(record: record, itemRecords: items, category: info.category, categoryId: info.categoryId)
      }
    }

    return AsyncThrowingStream { continuation in
      let cancellable = observation.start(
        in: databaseManager.reader,
        onError: { error in
          continuation.finish(throwing: error)
        },
        onChange: { sessions in
          continuation.yield(sessions)
        }
      )

      continuation.onTermination = { @Sendable _ in
        cancellable.cancel()
      }
    }
  }

  public func observeActiveSessions() -> AsyncThrowingStream<[ChecklistSession], any Error> {
    let observation = ValueObservation.tracking { db in
      let templates = try ChecklistTemplateRecord.fetchAll(db)
      let categoryInfoByTemplateId = Dictionary(uniqueKeysWithValues: templates.map { t in
        (t.id, (category: ChecklistCategory(rawValue: t.category) ?? ChecklistCategory(rawValue: t.category_id) ?? .routine, categoryId: t.category_id))
      })

      let records = try ChecklistSessionRecord
        .filter(ChecklistSessionRecord.Columns.status == ChecklistSessionStatus.inProgress.rawValue)
        .order(ChecklistSessionRecord.Columns.started_at.desc)
        .fetchAll(db)

      return try records.map { record in
        let items = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == record.id)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)
        let info = categoryInfoByTemplateId[record.template_id] ?? (.routine, ChecklistCategory.routine.rawValue)
        return try Self.mapSession(record: record, itemRecords: items, category: info.category, categoryId: info.categoryId)
      }
    }

    return AsyncThrowingStream { continuation in
      let cancellable = observation.start(
        in: databaseManager.reader,
        onError: { error in
          continuation.finish(throwing: error)
        },
        onChange: { sessions in
          continuation.yield(sessions)
        }
      )

      continuation.onTermination = { @Sendable _ in
        cancellable.cancel()
      }
    }
  }

  public func observeCompletedSessions() -> AsyncThrowingStream<[UUID: Date], any Error> {
    let observation = ValueObservation.tracking { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT template_id, MAX(completed_at) AS latest_completed_at
        FROM \(ChecklistSessionRecord.databaseTableName)
        WHERE status = ? AND completed_at IS NOT NULL
        GROUP BY template_id
        """,
        arguments: [ChecklistSessionStatus.completed.rawValue]
      )

      var result: [UUID: Date] = [:]
      result.reserveCapacity(rows.count)

      for row in rows {
        guard let templateIdString: String = row["template_id"],
              let templateId = UUID(uuidString: templateIdString),
              let completedAt: Date = row["latest_completed_at"] else {
          continue
        }
        result[templateId] = completedAt
      }

      return result
    }

    return AsyncThrowingStream { continuation in
      let cancellable = observation.start(
        in: databaseManager.reader,
        onError: { error in
          continuation.finish(throwing: error)
        },
        onChange: { dates in
          continuation.yield(dates)
        }
      )

      continuation.onTermination = { @Sendable _ in
        cancellable.cancel()
      }
    }
  }
}
