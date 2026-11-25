//
//  ChecklistSessionReconciler.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// Reconciles an active `.inProgress` checklist session when its parent template is edited.
///
/// Marine Safety & Transactional Atomicity:
/// This helper operates directly on `GRDB.Database` inside `ChecklistCatalogService.updateTemplate`'s
/// write transaction so template edits and active session reconciliation commit or roll back atomically,
/// guaranteeing checked steps and audited GPS coordinates are never lost or corrupted mid-maneuver.
enum ChecklistSessionReconciler {
  nonisolated static func reconcileActiveSessionIfPresent(
    for templateId: UUID,
    updatedTitle: String,
    updatedItems: [ChecklistTemplateItem],
    in db: Database
  ) throws {
    guard let activeSession = try ChecklistSessionRecord
      .filter(ChecklistSessionRecord.Columns.template_id == templateId.uuidString)
      .filter(ChecklistSessionRecord.Columns.status == ChecklistSessionStatus.inProgress.rawValue)
      .fetchOne(db) else {
      return
    }

    var updatedSession = activeSession
    updatedSession.template_title_snapshot = updatedTitle
    try updatedSession.update(db)

    let existingSessionItems = try ChecklistSessionItemRecord
      .filter(ChecklistSessionItemRecord.Columns.session_id == activeSession.id)
      .order(ChecklistSessionItemRecord.Columns.sort_order.asc)
      .fetchAll(db)

    var existingBySourceId: [String: ChecklistSessionItemRecord] = [:]
    for item in existingSessionItems {
      if let src = item.source_template_item_id {
        existingBySourceId[src] = item
      }
    }

    // Pass 1: Match items by exact source_template_item_id and mark consumed priors
    var matchedPriors: [ChecklistSessionItemRecord?] = Array(repeating: nil, count: updatedItems.count)
    var consumedPriorIds: Set<String> = []
    for (index, domainItem) in updatedItems.enumerated() {
      let sourceId = domainItem.id.uuidString
      if let prior = existingBySourceId.removeValue(forKey: sourceId) {
        matchedPriors[index] = prior
        consumedPriorIds.insert(prior.id)
      }
    }

    // Pass 2: Build FIFO queues by title from remaining unconsumed priors and match remaining items
    var unconsumedByTitle: [String: [ChecklistSessionItemRecord]] = [:]
    for item in existingSessionItems where !consumedPriorIds.contains(item.id) {
      unconsumedByTitle[item.title, default: []].append(item)
    }

    for (index, domainItem) in updatedItems.enumerated() where matchedPriors[index] == nil {
      if var queue = unconsumedByTitle[domainItem.title], !queue.isEmpty {
        let prior = queue.removeFirst()
        unconsumedByTitle[domainItem.title] = queue
        matchedPriors[index] = prior
      }
    }

    try ChecklistSessionItemRecord
      .filter(ChecklistSessionItemRecord.Columns.session_id == activeSession.id)
      .deleteAll(db)

    for (index, domainItem) in updatedItems.enumerated() {
      let sourceId = domainItem.id.uuidString
      let prior = matchedPriors[index]

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
}
