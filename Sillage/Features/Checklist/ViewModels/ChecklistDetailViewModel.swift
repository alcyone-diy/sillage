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

  var template: ChecklistTemplate?
  var session: ChecklistSession?
  var isLoading = false
  var isPerformingAction = false
  var errorMessage: String?
  var showResetConfirmation = false
  var showDeleteConfirmation = false

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
    session?.items ?? []
  }

  /// Identifies the first unchecked item in the list for progressive disclosure styling.
  var currentItemId: UUID? {
    items.first(where: { !$0.isChecked })?.id
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
      template = try await checklistService.fetchTemplate(id: templateId)
      session = try await checklistService.startSession(templateId: templateId)
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
    guard let session, !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      let coordinate = resolveAuditableCoordinate()
      _ = try await checklistService.setItemChecked(
        sessionId: session.id,
        itemId: item.id,
        isChecked: !item.isChecked,
        coordinate: coordinate
      )
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

    do {
      _ = try await checklistService.startSession(templateId: templateId)
    } catch {
      Logger.checklist.error("Failed to restart checklist session: \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
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
