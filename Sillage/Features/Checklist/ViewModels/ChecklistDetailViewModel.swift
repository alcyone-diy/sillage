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
import Observation
import OSLog

/// View model managing the interactive execution and detail state of a maritime checklist.
@MainActor
@Observable
final class ChecklistDetailViewModel {
  let templateId: UUID
  private let checklistService: any ChecklistServiceProtocol

  var template: ChecklistTemplate?
  var execution: ChecklistExecution?
  var isLoading = false
  var isPerformingAction = false
  var errorMessage: String?
  var showResetConfirmation = false
  var showDeleteConfirmation = false

  init(templateId: UUID, checklistService: any ChecklistServiceProtocol) {
    self.templateId = templateId
    self.checklistService = checklistService
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

  var isAllMandatorySatisfied: Bool {
    execution?.isAllMandatorySatisfied ?? false
  }

  var canComplete: Bool {
    guard let execution else { return false }
    return execution.status == .inProgress && execution.isAllMandatorySatisfied
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

  func toggleItem(_ item: ChecklistExecutionItem) async {
    guard let execution, !isPerformingAction else { return }
    isPerformingAction = true
    defer { isPerformingAction = false }

    do {
      let updated = try await checklistService.setItemChecked(
        executionId: execution.id,
        itemId: item.id,
        isChecked: !item.isChecked,
        coordinate: nil
      )
      self.execution = updated
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
      let updated = try await checklistService.completeExecution(
        executionId: execution.id,
        notes: nil
      )
      self.execution = updated
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
      let updated = try await checklistService.resetExecution(executionId: execution.id)
      self.execution = updated
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
      let newExecution = try await checklistService.startExecution(templateId: templateId)
      self.execution = newExecution
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
}
