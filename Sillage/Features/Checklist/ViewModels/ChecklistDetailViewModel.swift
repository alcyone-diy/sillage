//
//  ChecklistDetailViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import Observation
import OSLog

/// View model managing the interactive session and detail state of a maritime checklist.
@MainActor
@Observable
final class ChecklistDetailViewModel {
  let templateId: UUID
  private let checklistService: any ChecklistServiceProtocol
  private let locationProvider: (@MainActor () -> NavigationFix?)?

  var template: ChecklistTemplate? {
    didSet {
      updateCachedTemplateItems(from: template)
    }
  }
  var session: ChecklistSession?
  var isLoading = false
  var isPerformingAction = false
  var errorMessage: String?
  var showResetConfirmation = false
  var showDeleteConfirmation = false

  private var templateItems: [ChecklistSessionItem] = []
  private static let previewSessionId = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()

  init(
    templateId: UUID,
    checklistService: any ChecklistServiceProtocol,
    locationProvider: (@MainActor () -> NavigationFix?)? = nil
  ) {
    self.templateId = templateId
    self.checklistService = checklistService
    self.locationProvider = locationProvider
  }

  var title: String {
    session?.templateTitleSnapshot ?? template?.title ?? ""
  }

  var description: String? {
    template?.description
  }

  var category: ChecklistCategory? {
    template?.category
  }

  var items: [ChecklistSessionItem] {
    session?.items ?? templateItems
  }

  /// Identifies the first unchecked item in the list for progressive disclosure styling.
  var currentItemId: UUID? {
    items.first(where: { !$0.isChecked })?.stableId
  }

  var totalCount: Int {
    session?.totalCount ?? template?.items.count ?? 0
  }

  var completedCount: Int {
    session?.completedCount ?? 0
  }

  var progressRatio: Double {
    session?.progressRatio ?? 0.0
  }

  var isCompleted: Bool {
    session?.status == .completed
  }

  var canComplete: Bool {
    guard let session else { return false }
    return session.status == .inProgress && session.isFullyCompleted
  }

  var canReset: Bool {
    guard let session else { return false }
    return session.completedCount > 0
  }

  func load() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      self.template = try await checklistService.fetchTemplate(id: templateId)
      self.session = try await checklistService.fetchActiveSession(for: templateId)
    } catch {
      Logger.checklist.error("Failed to load checklist detail: \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  /// Reloads the template metadata and items after an edit.
  func refreshTemplate() async {
    do {
      if let updated = try await checklistService.fetchTemplate(id: templateId) {
        self.template = updated
      }
      if let active = try await checklistService.fetchActiveSession(for: templateId) {
        self.session = active
      }
    } catch {
      Logger.checklist.error("Failed to reload template: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func updateCachedTemplateItems(from template: ChecklistTemplate?) {
    guard let template else {
      self.templateItems = []
      return
    }
    self.templateItems = template.items.map { tItem in
      ChecklistSessionItem(
        id: tItem.id,
        sessionId: Self.previewSessionId,
        sourceTemplateItemId: tItem.id,
        sortOrder: tItem.sortOrder,
        title: tItem.title,
        detail: tItem.detail,
        isChecked: false,
        checkedAt: nil,
        coordinate: nil
      )
    }
  }

  /// Subscribes asynchronously to active sessions stream to drive UI reactively from the database.
  func observe() async {
    do {
      for try await activeSessions in checklistService.observeActiveSessions() {
        if Task.isCancelled { break }
        if let matching = activeSessions.first(where: { $0.templateId == templateId }) {
          self.session = matching
        } else if let currentId = session?.id {
          if let finished = try await checklistService.fetchSession(id: currentId) {
            self.session = finished
          }
        }
      }
    } catch {
      if !Task.isCancelled {
        Logger.checklist.error("Error observing active sessions: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  func toggleItem(_ item: ChecklistSessionItem) async {
    // UI-level guard: strictly drop simultaneous parasitic touches (rebound, double-tap, sea spray)
    guard !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      let coordinate = resolveAuditableCoordinate()

      let activeSession: ChecklistSession
      if let existing = session {
        activeSession = existing
      } else {
        activeSession = try await checklistService.startSession(templateId: templateId)
        self.session = activeSession
      }

      // Determine matching item in the active session using stableId
      guard let match = activeSession.items.first(where: { $0.stableId == item.stableId }) else {
        Logger.checklist.error("Item '\(item.stableId, privacy: .public)' not found in active session")
        return
      }

      let updated = try await checklistService.setItemChecked(
        sessionId: activeSession.id,
        itemId: match.id,
        isChecked: !item.isChecked,
        coordinate: coordinate
      )
      self.session = updated
    } catch {
      Logger.checklist.error("Failed to toggle checklist item '\(item.id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  func complete() async {
    guard let session, canComplete, !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      _ = try await checklistService.completeSession(
        sessionId: session.id,
        notes: nil
      )
    } catch {
      Logger.checklist.error("Failed to complete checklist '\(session.id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  func reset() async {
    guard let session, !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      _ = try await checklistService.resetSession(sessionId: session.id)
    } catch {
      Logger.checklist.error("Failed to reset checklist '\(session.id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  func restartSession() async {
    guard !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    // Lazy: clear the completed session so the UI returns to a clean, unchecked template state.
    // The next checked item will start a fresh session with started_at = Date().
    self.session = nil
  }

  func deleteTemplate() async -> Bool {
    guard template != nil, !isPerformingAction else { return false }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      try await checklistService.deleteTemplate(id: templateId)
      return true
    } catch {
      Logger.checklist.error("Failed to delete template '\(self.templateId, privacy: .public)': \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
      return false
    }
  }

  // MARK: - Defensive GPS Accuracy Resolution

  private static let maximumAuditableAccuracy = Measurement<UnitLength>(value: 50.0, unit: .meters)

  private func resolveAuditableCoordinate() -> CLLocationCoordinate2D? {
    guard let fix = locationProvider?() else { return nil }
    guard fix.horizontalAccuracy.value >= 0,
          fix.horizontalAccuracy <= Self.maximumAuditableAccuracy else {
      return nil
    }
    return fix.coordinate
  }
}
