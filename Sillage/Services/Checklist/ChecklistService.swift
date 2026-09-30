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

/// Thread-safe service managing nautical checklist templates and execution lifecycles.
public final class ChecklistService: ChecklistServiceProtocol {
  private let databaseManager: DatabaseManager
  private let throttler: ChecklistThrottler

  public init(databaseManager: DatabaseManager, throttler: ChecklistThrottler = ChecklistThrottler()) {
    self.databaseManager = databaseManager
    self.throttler = throttler
  }

  // MARK: - Static Pure Mappings (Zero Self-Capture, Zero Dummy Values)

  nonisolated private static func parseUUID(_ string: String, fieldName: String) throws(ChecklistExecutionError) -> UUID {
    guard let uuid = UUID(uuidString: string) else {
      throw ChecklistExecutionError.databaseInconsistency("Invalid UUID for field '\(fieldName)': '\(string)'")
    }
    return uuid
  }

  nonisolated private static func parseStatus(_ rawValue: String) throws(ChecklistExecutionError) -> ChecklistExecutionStatus {
    guard let status = ChecklistExecutionStatus(rawValue: rawValue) else {
      throw ChecklistExecutionError.databaseInconsistency("Unknown execution status: '\(rawValue)'")
    }
    return status
  }

  nonisolated public static func mapExecution(
    record: ChecklistSessionRecord,
    itemRecords: [ChecklistSessionItemRecord]
  ) throws(ChecklistExecutionError) -> ChecklistExecution {
    let executionId = try parseUUID(record.id, fieldName: "execution.id")
    let templateId = try parseUUID(record.template_id, fieldName: "execution.template_id")
    let status = try parseStatus(record.status)

    var domainItems: [ChecklistExecutionItem] = []
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
        throw ChecklistExecutionError.databaseInconsistency(
          "Spatial atomicity violated on checklist item '\(itemRecord.id)'"
        )
      }

      domainItems.append(ChecklistExecutionItem(
        id: itemId,
        executionId: executionId,
        sourceTemplateItemId: sourceTemplateItemId,
        sortOrder: itemRecord.sort_order,
        title: itemRecord.title,
        detail: itemRecord.detail,
        isChecked: itemRecord.is_checked,
        checkedAt: itemRecord.checked_at,
        coordinate: coordinate
      ))
    }

    return ChecklistExecution(
      id: executionId,
      templateId: templateId,
      templateTitleSnapshot: record.template_title_snapshot,
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

        guard let category = ChecklistCategory(rawValue: tRecord.category) else {
          throw ChecklistExecutionError.databaseInconsistency("Unknown checklist category: \(tRecord.category)")
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

      guard let category = ChecklistCategory(rawValue: tRecord.category) else {
        throw ChecklistExecutionError.databaseInconsistency("Unknown checklist category: \(tRecord.category)")
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
    try await databaseManager.write { db in
      let templateId = UUID()
      let now = Date()

      let templateRecord = ChecklistTemplateRecord(
        id: templateId.uuidString,
        title: title,
        description: description,
        category: category.rawValue,
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
    try await createTemplate(title: title, description: description, category: category, items: items)
  }

  public func updateTemplate(
    id: UUID,
    title: String,
    description: String? = nil,
    category: ChecklistCategory,
    items: [(id: UUID?, title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await databaseManager.write { db in
      guard let templateRecord = try ChecklistTemplateRecord.fetchOne(db, key: id.uuidString) else {
        throw ChecklistExecutionError.templateNotFound(id)
      }

      let now = Date()
      var updatedTemplateRecord = templateRecord
      updatedTemplateRecord.title = title
      updatedTemplateRecord.description = description
      updatedTemplateRecord.category = category.rawValue
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

      // Update active execution snapshot and items if in progress
      if let activeExecution = try ChecklistSessionRecord
        .filter(ChecklistSessionRecord.Columns.template_id == id.uuidString)
        .filter(ChecklistSessionRecord.Columns.status == ChecklistExecutionStatus.inProgress.rawValue)
        .fetchOne(db) {
        var updatedExecution = activeExecution
        updatedExecution.template_title_snapshot = title
        try updatedExecution.update(db)

        let existingExecutionItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.execution_id == activeExecution.id)
          .fetchAll(db)

        var existingBySourceId: [String: ChecklistSessionItemRecord] = [:]
        var existingByTitle: [String: ChecklistSessionItemRecord] = [:]
        for item in existingExecutionItems {
          if let src = item.source_template_item_id {
            existingBySourceId[src] = item
          }
          existingByTitle[item.title] = item
        }

        try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.execution_id == activeExecution.id)
          .deleteAll(db)

        for (index, domainItem) in domainItems.enumerated() {
          let sourceId = domainItem.id.uuidString
          let prior = existingBySourceId[sourceId] ?? existingByTitle[domainItem.title]
          let execRecord = ChecklistSessionItemRecord(
            id: prior?.id ?? UUID().uuidString,
            execution_id: activeExecution.id,
            source_template_item_id: sourceId,
            sort_order: index,
            title: domainItem.title,
            detail: domainItem.detail,
            is_checked: prior?.is_checked ?? false,
            checked_at: prior?.checked_at,
            latitude_deg: prior?.latitude_deg,
            longitude_deg: prior?.longitude_deg
          )
          try execRecord.insert(db)
        }
      }

      Logger.checklist.info("Successfully updated template '\(id.uuidString, privacy: .public)'")

      return ChecklistTemplate(
        id: id,
        title: title,
        description: description,
        category: category,
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
    try await updateTemplate(id: id, title: title, description: description, category: category, items: items)
  }

  public func deleteTemplate(id: UUID) async throws {
    try await databaseManager.write { db in
      guard let template = try ChecklistTemplateRecord.fetchOne(db, key: id.uuidString) else {
        throw ChecklistExecutionError.templateNotFound(id)
      }

      let sessions = try ChecklistSessionRecord
        .filter(ChecklistSessionRecord.Columns.template_id == id.uuidString)
        .fetchAll(db)
      for session in sessions {
        try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.execution_id == session.id)
          .deleteAll(db)
        try session.delete(db)
      }

      try ChecklistTemplateItemRecord
        .filter(ChecklistTemplateItemRecord.Columns.template_id == id.uuidString)
        .deleteAll(db)

      try template.delete(db)
      Logger.checklist.info("Successfully deleted template '\(id.uuidString, privacy: .public)'")
    }
  }

  public func deleteCustomTemplate(id: UUID) async throws {
    try await deleteTemplate(id: id)
  }

  // MARK: - Execution Lifecycle (Get-or-Create)

  public func startExecution(templateId: UUID) async throws(ChecklistExecutionError) -> ChecklistExecution {
    do {
      return try await databaseManager.write { db in
        // 1. Transparent Get-or-Create: Resume existing in-progress execution if present
        let activeRecord = try ChecklistSessionRecord
          .filter(ChecklistSessionRecord.Columns.template_id == templateId.uuidString)
          .filter(ChecklistSessionRecord.Columns.status == ChecklistExecutionStatus.inProgress.rawValue)
          .fetchOne(db)

        if let existingRecord = activeRecord {
          Logger.checklist.info(
            "Resuming existing active session for template '\(templateId.uuidString, privacy: .public)'"
          )
          let existingItems = try ChecklistSessionItemRecord
            .filter(ChecklistSessionItemRecord.Columns.execution_id == existingRecord.id)
            .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
            .fetchAll(db)
          return try Self.mapExecution(record: existingRecord, itemRecords: existingItems)
        }

        // 2. Normal path: Instantiate new execution from template snapshot
        guard let templateRecord = try ChecklistTemplateRecord.fetchOne(db, key: templateId.uuidString) else {
          throw ChecklistExecutionError.templateNotFound(templateId)
        }

        let templateItems = try ChecklistTemplateItemRecord
          .filter(ChecklistTemplateItemRecord.Columns.template_id == templateId.uuidString)
          .order(ChecklistTemplateItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        let executionId = UUID()
        let now = Date()

        let executionRecord = ChecklistSessionRecord(
          id: executionId.uuidString,
          template_id: templateId.uuidString,
          template_title_snapshot: templateRecord.title,
          status: ChecklistExecutionStatus.inProgress.rawValue,
          started_at: now,
          completed_at: nil,
          notes: nil
        )
        try executionRecord.insert(db)

        var itemRecords: [ChecklistSessionItemRecord] = []
        for item in templateItems {
          let itemRecord = ChecklistSessionItemRecord(
            id: UUID().uuidString,
            execution_id: executionId.uuidString,
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

        Logger.checklist.info("Started new checklist execution '\(executionId.uuidString, privacy: .public)'")
        return try Self.mapExecution(record: executionRecord, itemRecords: itemRecords)
      }
    } catch let error as ChecklistExecutionError {
      throw error
    } catch {
      Logger.checklist.error("Failed to start checklist execution: \(error, privacy: .public)")
      throw ChecklistExecutionError.databaseFailure(error.localizedDescription)
    }
  }

  public func setItemChecked(
    executionId: UUID,
    itemId: UUID,
    isChecked: Bool,
    coordinate: CLLocationCoordinate2D? = nil
  ) async throws(ChecklistExecutionError) -> ChecklistExecution {
    // 1. Debounce rapid vibrations / wet touch screen taps
    guard await throttler.shouldProcessAction(for: itemId) else {
      Logger.checklist.debug("Debouncing action on item '\(itemId, privacy: .public)'")
      do {
        guard let current = try await fetchExecution(id: executionId) else {
          throw ChecklistExecutionError.executionNotFound(executionId)
        }
        return current
      } catch let error as ChecklistExecutionError {
        throw error
      } catch {
        throw ChecklistExecutionError.databaseFailure(error.localizedDescription)
      }
    }

    do {
      return try await databaseManager.write { db in
        guard let executionRecord = try ChecklistSessionRecord.fetchOne(db, key: executionId.uuidString) else {
          throw ChecklistExecutionError.executionNotFound(executionId)
        }
        guard executionRecord.status == ChecklistExecutionStatus.inProgress.rawValue else {
          throw ChecklistExecutionError.executionAlreadyFinished(executionId)
        }
        guard var itemRecord = try ChecklistSessionItemRecord.fetchOne(db, key: itemId.uuidString) else {
          throw ChecklistExecutionError.itemNotFound(itemId)
        }

        // 2. Strict Idempotency: Return immediately with 0 disk write if state is identical
        if itemRecord.is_checked == isChecked {
          let allItems = try ChecklistSessionItemRecord
            .filter(ChecklistSessionItemRecord.Columns.execution_id == executionId.uuidString)
            .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
            .fetchAll(db)
          return try Self.mapExecution(record: executionRecord, itemRecords: allItems)
        }

        itemRecord.is_checked = isChecked
        itemRecord.checked_at = isChecked ? Date() : nil
        itemRecord.latitude_deg = isChecked ? coordinate?.latitude : nil
        itemRecord.longitude_deg = isChecked ? coordinate?.longitude : nil
        try itemRecord.update(db)

        let allItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.execution_id == executionId.uuidString)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        return try Self.mapExecution(record: executionRecord, itemRecords: allItems)
      }
    } catch let error as ChecklistExecutionError {
      throw error
    } catch {
      throw ChecklistExecutionError.databaseFailure(error.localizedDescription)
    }
  }

  public func completeExecution(
    executionId: UUID,
    notes: String? = nil
  ) async throws(ChecklistExecutionError) -> ChecklistExecution {
    do {
      return try await databaseManager.write { db in
        guard var executionRecord = try ChecklistSessionRecord.fetchOne(db, key: executionId.uuidString) else {
          throw ChecklistExecutionError.executionNotFound(executionId)
        }
        guard executionRecord.status == ChecklistExecutionStatus.inProgress.rawValue else {
          throw ChecklistExecutionError.executionAlreadyFinished(executionId)
        }

        let allItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.execution_id == executionId.uuidString)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        executionRecord.status = ChecklistExecutionStatus.completed.rawValue
        executionRecord.completed_at = Date()
        executionRecord.notes = notes
        try executionRecord.update(db)

        Logger.checklist.info("Completed checklist execution '\(executionId.uuidString, privacy: .public)'")
        return try Self.mapExecution(record: executionRecord, itemRecords: allItems)
      }
    } catch let error as ChecklistExecutionError {
      throw error
    } catch {
      throw ChecklistExecutionError.databaseFailure(error.localizedDescription)
    }
  }

  public func resetExecution(executionId: UUID) async throws(ChecklistExecutionError) -> ChecklistExecution {
    do {
      return try await databaseManager.write { db in
        guard let executionRecord = try ChecklistSessionRecord.fetchOne(db, key: executionId.uuidString) else {
          throw ChecklistExecutionError.executionNotFound(executionId)
        }
        guard executionRecord.status == ChecklistExecutionStatus.inProgress.rawValue else {
          throw ChecklistExecutionError.executionAlreadyFinished(executionId)
        }

        try db.execute(
          sql: """
          UPDATE \(ChecklistSessionItemRecord.databaseTableName)
          SET is_checked = 0, checked_at = NULL, latitude_deg = NULL, longitude_deg = NULL
          WHERE execution_id = ?
          """,
          arguments: [executionId.uuidString]
        )

        let allItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.execution_id == executionId.uuidString)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        Logger.checklist.info("Reset checklist execution '\(executionId.uuidString, privacy: .public)'")
        return try Self.mapExecution(record: executionRecord, itemRecords: allItems)
      }
    } catch let error as ChecklistExecutionError {
      throw error
    } catch {
      throw ChecklistExecutionError.databaseFailure(error.localizedDescription)
    }
  }

  public func abandonExecution(executionId: UUID) async throws(ChecklistExecutionError) -> ChecklistExecution {
    do {
      return try await databaseManager.write { db in
        guard var executionRecord = try ChecklistSessionRecord.fetchOne(db, key: executionId.uuidString) else {
          throw ChecklistExecutionError.executionNotFound(executionId)
        }
        guard executionRecord.status == ChecklistExecutionStatus.inProgress.rawValue else {
          throw ChecklistExecutionError.executionAlreadyFinished(executionId)
        }

        executionRecord.status = ChecklistExecutionStatus.abandoned.rawValue
        executionRecord.completed_at = Date()
        try executionRecord.update(db)

        let allItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.execution_id == executionId.uuidString)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        Logger.checklist.info("Abandoned checklist execution '\(executionId.uuidString, privacy: .public)'")
        return try Self.mapExecution(record: executionRecord, itemRecords: allItems)
      }
    } catch let error as ChecklistExecutionError {
      throw error
    } catch {
      throw ChecklistExecutionError.databaseFailure(error.localizedDescription)
    }
  }

  public func fetchActiveExecution(for templateId: UUID) async throws -> ChecklistExecution? {
    try await databaseManager.reader.read { db in
      guard let record = try ChecklistSessionRecord
        .filter(ChecklistSessionRecord.Columns.template_id == templateId.uuidString)
        .filter(ChecklistSessionRecord.Columns.status == ChecklistExecutionStatus.inProgress.rawValue)
        .fetchOne(db) else {
        return nil
      }

      let items = try ChecklistSessionItemRecord
        .filter(ChecklistSessionItemRecord.Columns.execution_id == record.id)
        .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
        .fetchAll(db)

      return try Self.mapExecution(record: record, itemRecords: items)
    }
  }

  public func fetchExecution(id: UUID) async throws -> ChecklistExecution? {
    try await databaseManager.reader.read { db in
      guard let record = try ChecklistSessionRecord.fetchOne(db, key: id.uuidString) else {
        return nil
      }

      let items = try ChecklistSessionItemRecord
        .filter(ChecklistSessionItemRecord.Columns.execution_id == record.id)
        .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
        .fetchAll(db)

      return try Self.mapExecution(record: record, itemRecords: items)
    }
  }

  public func fetchRecentExecutions(limit: Int) async throws -> [ChecklistExecution] {
    try await databaseManager.reader.read { db in
      let records = try ChecklistSessionRecord
        .order(ChecklistSessionRecord.Columns.started_at.desc)
        .limit(limit)
        .fetchAll(db)

      return try records.map { record in
        let items = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.execution_id == record.id)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)
        return try Self.mapExecution(record: record, itemRecords: items)
      }
    }
  }

  public func seedDefaultTemplatesIfNeeded() async throws {
    try await databaseManager.write { db in
      try ChecklistSeeder.seedDefaultTemplatesIfNeeded(in: db)
    }
  }

  // MARK: - Reactive Observation (AsyncThrowingStream, No Task.detached)

  public func observeActiveExecutions() -> AsyncThrowingStream<[ChecklistExecution], any Error> {
    let observation = ValueObservation.tracking { db in
      let records = try ChecklistSessionRecord
        .filter(ChecklistSessionRecord.Columns.status == ChecklistExecutionStatus.inProgress.rawValue)
        .order(ChecklistSessionRecord.Columns.started_at.desc)
        .fetchAll(db)

      return try records.map { record in
        let items = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.execution_id == record.id)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)
        return try Self.mapExecution(record: record, itemRecords: items)
      }
    }

    return AsyncThrowingStream { continuation in
      let cancellable = observation.start(
        in: databaseManager.reader,
        onError: { error in
          continuation.finish(throwing: error)
        },
        onChange: { executions in
          continuation.yield(executions)
        }
      )

      continuation.onTermination = { @Sendable _ in
        cancellable.cancel()
      }
    }
  }
}
