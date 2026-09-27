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

/// View model managing the interactive execution and detail state of a maritime checklist.
@MainActor
@Observable
final class ChecklistDetailViewModel {
  let templateId: UUID
  private let checklistService: any ChecklistServiceProtocol
  private let locationProvider: (@MainActor () -> NavigationFix?)?

  var template: ChecklistTemplate?
  var execution: ChecklistExecution?
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
    execution?.templateTitleSnapshot ?? template?.title ?? ""
  }

  var description: String? {
    template?.description
  }

  var category: ChecklistCategory? {
    template?.category
  }

  var items: [ChecklistExecutionItem] {
    execution?.items ?? []
  }

  /// Identifies the first unchecked item in the list for progressive disclosure styling.
  var currentItemId: UUID? {
    items.first(where: { !$0.isChecked })?.id
  }

  var totalCount: Int {
    execution?.totalCount ?? template?.items.count ?? 0
  }

  var completedCount: Int {
    execution?.completedCount ?? 0
  }

  var progressRatio: Double {
    execution?.progressRatio ?? 0.0
  }

  var isCompleted: Bool {
    execution?.status == .completed
  }

  var canComplete: Bool {
    guard let execution else { return false }
    return execution.status == .inProgress && execution.isFullyCompleted
  }

  var canReset: Bool {
    guard let execution else { return false }
    return execution.completedCount > 0
  }

  var canDeleteTemplate: Bool {
    guard let template else { return false }
    return !template.isSystem
  }

  func load() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      template = try await checklistService.fetchTemplate(id: templateId)
      execution = try await checklistService.startExecution(templateId: templateId)
    } catch {
      Logger.checklist.error("Failed to load checklist detail: \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  /// Subscribes asynchronously to active executions stream to drive UI reactively from the database.
  func observe() async {
    do {
      for try await activeExecutions in checklistService.observeActiveExecutions() {
        if Task.isCancelled { break }
        if let matching = activeExecutions.first(where: { $0.templateId == templateId }) {
          self.execution = matching
        } else if let currentId = execution?.id {
          if let finished = try await checklistService.fetchExecution(id: currentId) {
            self.execution = finished
          }
        }
      }
    } catch {
      if !Task.isCancelled {
        Logger.checklist.error("Error observing active executions: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  func toggleItem(_ item: ChecklistExecutionItem) async {
    guard let execution, !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      let coordinate = resolveAuditableCoordinate()
      _ = try await checklistService.setItemChecked(
        executionId: execution.id,
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
    guard let execution, canComplete, !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      _ = try await checklistService.completeExecution(
        executionId: execution.id,
        notes: nil
      )
    } catch {
      Logger.checklist.error("Failed to complete checklist '\(execution.id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  func reset() async {
    guard let execution, !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      _ = try await checklistService.resetExecution(executionId: execution.id)
    } catch {
      Logger.checklist.error("Failed to reset checklist '\(execution.id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  func restartSession() async {
    guard !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      _ = try await checklistService.startExecution(templateId: templateId)
    } catch {
      Logger.checklist.error("Failed to restart checklist session: \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  func deleteTemplate() async -> Bool {
    guard canDeleteTemplate, !isPerformingAction else { return false }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      try await checklistService.deleteCustomTemplate(id: templateId)
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
