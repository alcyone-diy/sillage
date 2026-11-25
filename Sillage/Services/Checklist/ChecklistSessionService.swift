//
//  ChecklistSessionService.swift
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
import OSLog

/// Service managing nautical checklist session lifecycles, tap throttling, and reactive observations.
@MainActor
public final class ChecklistSessionService: ChecklistSessionServiceProtocol, Sendable {
  /// Retention duration in hours for recently completed sessions in active observation.
  nonisolated public static let completedSessionRetentionHours: Int = 48

  private let databaseManager: DatabaseManager
  private let throttler: ChecklistThrottler

  public init(
    databaseManager: DatabaseManager,
    throttler: ChecklistThrottler = ChecklistThrottler()
  ) {
    self.databaseManager = databaseManager
    self.throttler = throttler
  }

  // MARK: - Session Lifecycle (Get-or-Create)

  public func startSession(templateId: UUID) async throws(ChecklistError) -> ChecklistSession {
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
          let categoryId = try ChecklistDomainMapper.fetchCategoryInfo(for: templateId.uuidString, in: db)
          let existingItems = try ChecklistSessionItemRecord
            .filter(ChecklistSessionItemRecord.Columns.session_id == existingRecord.id)
            .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
            .fetchAll(db)
          return try ChecklistDomainMapper.mapSession(
            record: existingRecord,
            itemRecords: existingItems,
            categoryId: categoryId
          )
        }

        // 2. Normal path: Instantiate new session from template snapshot
        guard let templateRecord = try ChecklistTemplateRecord.fetchOne(db, key: templateId.uuidString) else {
          throw ChecklistError.templateNotFound(templateId)
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
        itemRecords.reserveCapacity(templateItems.count)

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

        let categoryId = templateRecord.category_id
        Logger.checklist.info("Started new checklist session '\(sessionId.uuidString, privacy: .public)'")
        return try ChecklistDomainMapper.mapSession(
          record: sessionRecord,
          itemRecords: itemRecords,
          categoryId: categoryId
        )
      }
    } catch let error as ChecklistError {
      throw error
    } catch {
      Logger.checklist.error("Failed to start checklist session: \(error, privacy: .public)")
      throw ChecklistError.databaseFailure(error.localizedDescription)
    }
  }

  public func setItemChecked(
    sessionId: UUID,
    itemId: UUID,
    isChecked: Bool,
    coordinate: CLLocationCoordinate2D? = nil
  ) async throws(ChecklistError) -> ChecklistSession {
    // 1. Debounce rapid vibrations / wet touch screen taps
    guard await throttler.shouldProcessAction(for: itemId) else {
      Logger.checklist.debug("Debouncing action on item '\(itemId, privacy: .public)'")
      do {
        guard let current = try await fetchSession(id: sessionId) else {
          throw ChecklistError.sessionNotFound(sessionId)
        }
        return current
      } catch let error as ChecklistError {
        throw error
      } catch {
        throw ChecklistError.databaseFailure(error.localizedDescription)
      }
    }

    do {
      return try await databaseManager.write { db in
        guard let sessionRecord = try ChecklistSessionRecord.fetchOne(db, key: sessionId.uuidString) else {
          throw ChecklistError.sessionNotFound(sessionId)
        }
        guard sessionRecord.status == ChecklistSessionStatus.inProgress.rawValue else {
          throw ChecklistError.sessionAlreadyFinished(sessionId)
        }
        guard var itemRecord = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.id == itemId.uuidString)
          .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
          .fetchOne(db) else {
          throw ChecklistError.itemNotFound(itemId)
        }

        // 2. Strict Idempotency: Return immediately with 0 disk write if state is identical
        if itemRecord.is_checked == isChecked {
          let allItems = try ChecklistSessionItemRecord
            .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
            .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
            .fetchAll(db)
          let categoryId = try ChecklistDomainMapper.fetchCategoryInfo(for: sessionRecord.template_id, in: db)
          return try ChecklistDomainMapper.mapSession(
            record: sessionRecord,
            itemRecords: allItems,
            categoryId: categoryId
          )
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
          updatedSessionRecord.started_at = Date()
          try updatedSessionRecord.update(db)
        }

        let allItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        let categoryId = try ChecklistDomainMapper.fetchCategoryInfo(for: sessionRecord.template_id, in: db)
        return try ChecklistDomainMapper.mapSession(
          record: updatedSessionRecord,
          itemRecords: allItems,
          categoryId: categoryId
        )
      }
    } catch let error as ChecklistError {
      await throttler.reset(for: itemId)
      throw error
    } catch {
      await throttler.reset(for: itemId)
      throw ChecklistError.databaseFailure(error.localizedDescription)
    }
  }

  public func completeSession(
    sessionId: UUID,
    notes: String? = nil
  ) async throws(ChecklistError) -> ChecklistSession {
    do {
      return try await databaseManager.write { db in
        guard var sessionRecord = try ChecklistSessionRecord.fetchOne(db, key: sessionId.uuidString) else {
          throw ChecklistError.sessionNotFound(sessionId)
        }
        guard sessionRecord.status == ChecklistSessionStatus.inProgress.rawValue else {
          throw ChecklistError.sessionAlreadyFinished(sessionId)
        }

        let allItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        sessionRecord.status = ChecklistSessionStatus.completed.rawValue
        sessionRecord.completed_at = Date()
        sessionRecord.notes = notes
        try sessionRecord.update(db)

        let categoryId = try ChecklistDomainMapper.fetchCategoryInfo(for: sessionRecord.template_id, in: db)
        Logger.checklist.info("Completed checklist session '\(sessionId.uuidString, privacy: .public)'")
        return try ChecklistDomainMapper.mapSession(
          record: sessionRecord,
          itemRecords: allItems,
          categoryId: categoryId
        )
      }
    } catch let error as ChecklistError {
      throw error
    } catch {
      throw ChecklistError.databaseFailure(error.localizedDescription)
    }
  }

  public func deleteSession(sessionId: UUID) async throws(ChecklistError) {
    do {
      try await databaseManager.write { db in
        guard let sessionRecord = try ChecklistSessionRecord.fetchOne(db, key: sessionId.uuidString) else {
          throw ChecklistError.sessionNotFound(sessionId)
        }

        try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
          .deleteAll(db)

        try sessionRecord.delete(db)

        Logger.checklist.info("Deleted checklist session '\(sessionId.uuidString, privacy: .public)'")
      }
    } catch let error as ChecklistError {
      throw error
    } catch {
      throw ChecklistError.databaseFailure(error.localizedDescription)
    }
  }

  public func abandonSession(sessionId: UUID) async throws(ChecklistError) -> ChecklistSession {
    do {
      return try await databaseManager.write { db in
        guard var sessionRecord = try ChecklistSessionRecord.fetchOne(db, key: sessionId.uuidString) else {
          throw ChecklistError.sessionNotFound(sessionId)
        }
        guard sessionRecord.status == ChecklistSessionStatus.inProgress.rawValue else {
          throw ChecklistError.sessionAlreadyFinished(sessionId)
        }

        sessionRecord.status = ChecklistSessionStatus.abandoned.rawValue
        sessionRecord.completed_at = Date()
        try sessionRecord.update(db)

        let allItems = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == sessionId.uuidString)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)

        let categoryId = try ChecklistDomainMapper.fetchCategoryInfo(for: sessionRecord.template_id, in: db)
        Logger.checklist.info("Abandoned checklist session '\(sessionId.uuidString, privacy: .public)'")
        return try ChecklistDomainMapper.mapSession(
          record: sessionRecord,
          itemRecords: allItems,
          categoryId: categoryId
        )
      }
    } catch let error as ChecklistError {
      throw error
    } catch {
      throw ChecklistError.databaseFailure(error.localizedDescription)
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

      let categoryId = try ChecklistDomainMapper.fetchCategoryInfo(for: record.template_id, in: db)
      return try ChecklistDomainMapper.mapSession(record: record, itemRecords: items, categoryId: categoryId)
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

      let categoryId = try ChecklistDomainMapper.fetchCategoryInfo(for: record.template_id, in: db)
      return try ChecklistDomainMapper.mapSession(record: record, itemRecords: items, categoryId: categoryId)
    }
  }

  public func fetchRecentSessions(limit: Int) async throws -> [ChecklistSession] {
    try await databaseManager.reader.read { db in
      let templates = try ChecklistTemplateRecord.fetchAll(db)
      let categoryIdByTemplateId = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0.category_id) })

      let records = try ChecklistSessionRecord
        .order(ChecklistSessionRecord.Columns.started_at.desc)
        .limit(limit)
        .fetchAll(db)

      return try records.map { record in
        let items = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == record.id)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)
        let categoryId = try ChecklistDomainMapper.resolveCategoryId(
          for: record.template_id,
          in: categoryIdByTemplateId
        )
        return try ChecklistDomainMapper.mapSession(record: record, itemRecords: items, categoryId: categoryId)
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

  // MARK: - Reactive Observation (AsyncThrowingStream, No Task.detached)

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
    let reader = databaseManager.reader

    let observation = ValueObservation.tracking { db in
      let templates = try ChecklistTemplateRecord.fetchAll(db)
      let categoryIdByTemplateId = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0.category_id) })

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
        let categoryId = try ChecklistDomainMapper.resolveCategoryId(
          for: record.template_id,
          in: categoryIdByTemplateId
        )
        return try ChecklistDomainMapper.mapSession(record: record, itemRecords: items, categoryId: categoryId)
      }
    }

    return AsyncThrowingStream { continuation in
      let cancellable = observation.start(
        in: reader,
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
    let reader = databaseManager.reader

    let observation = ValueObservation.tracking { db in
      let templates = try ChecklistTemplateRecord.fetchAll(db)
      let categoryIdByTemplateId = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0.category_id) })

      let records = try ChecklistSessionRecord
        .filter(ChecklistSessionRecord.Columns.status == ChecklistSessionStatus.inProgress.rawValue)
        .order(ChecklistSessionRecord.Columns.started_at.desc)
        .fetchAll(db)

      return try records.map { record in
        let items = try ChecklistSessionItemRecord
          .filter(ChecklistSessionItemRecord.Columns.session_id == record.id)
          .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
          .fetchAll(db)
        let categoryId = try ChecklistDomainMapper.resolveCategoryId(
          for: record.template_id,
          in: categoryIdByTemplateId
        )
        return try ChecklistDomainMapper.mapSession(record: record, itemRecords: items, categoryId: categoryId)
      }
    }

    return AsyncThrowingStream { continuation in
      let cancellable = observation.start(
        in: reader,
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
    let reader = databaseManager.reader

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
        in: reader,
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
