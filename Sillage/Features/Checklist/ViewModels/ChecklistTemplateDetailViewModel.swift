//
//  ChecklistTemplateDetailViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import SwiftUI
import Observation
import OSLog

/// Represents the usage or execution status of a checklist template.
public enum ChecklistUsageStatus: Equatable, Sendable {
  case inProgress(ChecklistSession)
  case completed(Date)
  case neverUsed
}

/// A draft model representing a single step being authored within a checklist template.
public struct ChecklistItemDraft: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var detail: String

  public init(
    id: UUID = UUID(),
    title: String = "",
    detail: String = ""
  ) {
    self.id = id
    self.title = title
    self.detail = detail
  }
}

/// A unified view model managing the presentation, editing, reordering, and session launching for a checklist template.
@MainActor
@Observable
public final class ChecklistTemplateDetailViewModel {
  public private(set) var templateId: UUID?
  private let checklistService: any ChecklistServiceProtocol

  public private(set) var template: ChecklistTemplate?
  public private(set) var activeSession: ChecklistSession?
  public private(set) var latestCompletionDate: Date?
  public private(set) var isLoading: Bool = false
  public private(set) var isSaving: Bool = false
  public var isEditable: Bool
  public var alertTitle: String = "Error"
  public var errorMessage: String?

  public var title: String = ""
  public var descriptionText: String = ""
  public var category: ChecklistCategory = .routine
  public var items: [ChecklistItemDraft] = []

  public var description: String? {
    let trimmed = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Returns whether this view model is modifying an existing template or authoring a new one.
  public var isEditing: Bool {
    templateId != nil
  }

  /// Returns true if creating a new template (no templateId).
  public var isNew: Bool {
    templateId == nil
  }

  /// Indicates whether deletion is allowed (hides/disables the button in the UI)
  public var canDelete: Bool {
    templateId != nil && !isSaving
  }

  public var hasActiveSession: Bool {
    activeSession != nil && activeSession?.status == .inProgress && (activeSession?.completedCount ?? 0) > 0
  }

  /// Active session if currently in progress with at least one item checked.
  public var activeSessionWithProgress: ChecklistSession? {
    hasActiveSession ? activeSession : nil
  }

  /// The strongly typed execution/usage status of this checklist template.
  public var usageStatus: ChecklistUsageStatus {
    if let activeSession = activeSessionWithProgress {
      return .inProgress(activeSession)
    } else if let latestCompletionDate {
      return .completed(latestCompletionDate)
    } else {
      return .neverUsed
    }
  }

  /// A localized, human-readable description of the template's usage status for display in the UI.
  public var usageStatusDescription: String {
    switch usageStatus {
    case .inProgress(let session):
      let dateString = session.startedAt.formatted(date: .abbreviated, time: .shortened)
      return String(
        localized: "Started \(dateString) • \(session.completedCount)/\(session.totalCount) checked",
        comment: "Checklist template usage status description when an execution session is currently in progress."
      )
    case .completed(let date):
      let dateString = date.formatted(date: .abbreviated, time: .shortened)
      return String(
        localized: "Completed \(dateString)",
        comment: "Checklist template usage status description when the checklist was previously completed."
      )
    case .neverUsed:
      return String(
        localized: "Never used",
        comment: "Checklist template usage status description when the checklist has never been executed."
      )
    }
  }

  /// Returns true if the template has a valid non-empty title and at least one step with a non-empty title.
  public var isValid: Bool {
    validationErrorMessage == nil
  }

  /// Explains why the checklist template cannot be saved, or returns nil if valid.
  public var validationErrorMessage: String? {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let validItems = items.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    let isTitleEmpty = trimmedTitle.isEmpty
    let isStepsEmpty = validItems.isEmpty

    if isTitleEmpty && isStepsEmpty {
      return String(localized: "Please provide a title and at least one step for your checklist.")
    } else if isTitleEmpty {
      return String(localized: "Please provide a title for your checklist.")
    } else if isStepsEmpty {
      return String(localized: "Please add at least one step with a title to your checklist.")
    }
    return nil
  }

  public init(
    templateId: UUID? = nil,
    template: ChecklistTemplate? = nil,
    checklistService: any ChecklistServiceProtocol,
    startEditable: Bool = false,
    initialCategory: ChecklistCategory = .routine
  ) {
    self.templateId = templateId ?? template?.id
    self.checklistService = checklistService
    self.isEditable = (templateId == nil && template == nil) ? true : startEditable

    if let template {
      self.template = template
      populate(from: template)
    } else if templateId == nil {
      self.category = initialCategory
      self.items = [ChecklistItemDraft()]
    }
  }

  /// Loads the checklist template and any currently active session.
  public func load() async {
    guard let templateId else {
      if items.isEmpty {
        items = [ChecklistItemDraft()]
      }
      return
    }

    isLoading = true
    defer { isLoading = false }
    errorMessage = nil

    do {
      let fetchedTemplate = try await checklistService.fetchTemplate(id: templateId)
      self.template = fetchedTemplate
      if let fetchedTemplate {
        populate(from: fetchedTemplate)
      }
      self.activeSession = try await checklistService.fetchActiveSession(for: templateId)
      self.latestCompletionDate = try await checklistService.fetchLatestCompletionDate(for: templateId)
    } catch {
      Logger.checklist.error("Failed to load checklist template \(templateId.uuidString, privacy: .public): \(String(reflecting: error), privacy: .public)")
      errorMessage = ChecklistSessionError.userMessage(for: error)
    }
  }

  /// Loads the template and concurrently observes active and completed sessions using structured concurrency.
  public func startObserving() async {
    await load()
    guard templateId != nil else { return }

    await withTaskGroup(of: Void.self) { group in
      group.addTask { @MainActor [weak self] in
        await self?.observeActiveSessions()
      }
      group.addTask { @MainActor [weak self] in
        await self?.observeCompletedSessions()
      }
    }
  }

  /// Observes active in-progress checklist sessions for this template.
  public func observeActiveSessions() async {
    guard let templateId else { return }
    do {
      for try await sessions in checklistService.observeActiveSessions() {
        if Task.isCancelled { break }
        self.activeSession = sessions.first {
          $0.templateId == templateId &&
          $0.status == .inProgress
        }
      }
    } catch {
      if !Task.isCancelled {
        Logger.checklist.error("Error observing active sessions: \(String(reflecting: error), privacy: .public)")
      }
    }
  }

  /// Observes latest completion dates for this template.
  public func observeCompletedSessions() async {
    guard let templateId else { return }
    do {
      for try await dates in checklistService.observeCompletedSessions() {
        if Task.isCancelled { break }
        self.latestCompletionDate = dates[templateId]
      }
    } catch {
      if !Task.isCancelled {
        Logger.checklist.error("Error observing completed sessions: \(String(reflecting: error), privacy: .public)")
      }
    }
  }

  private func populate(from template: ChecklistTemplate) {
    self.title = template.title
    self.descriptionText = template.description ?? ""
    self.category = template.category
    let mapped = template.items.sorted { $0.sortOrder < $1.sortOrder }.map { item in
      ChecklistItemDraft(
        id: item.id,
        title: item.title,
        detail: item.detail ?? ""
      )
    }
    self.items = mapped.isEmpty ? [ChecklistItemDraft()] : mapped
  }

  /// Reverts any in-progress edits back to the loaded template state.
  public func revert() {
    if let template {
      populate(from: template)
      isEditable = false
    } else {
      title = ""
      descriptionText = ""
      category = .routine
      items = [ChecklistItemDraft()]
    }
  }

  /// Starts a new session or transparently resumes the active session for this template.
  /// - Returns: The UUID of the session, or `nil` on failure.
  public func startOrResumeSession() async -> UUID? {
    guard let templateId else { return nil }
    do {
      let session = try await checklistService.startSession(templateId: templateId)
      self.activeSession = session
      return session.id
    } catch {
      Logger.checklist.error("Failed to start or resume checklist session: \(String(reflecting: error), privacy: .public)")
      errorMessage = ChecklistSessionError.userMessage(for: error)
      return nil
    }
  }

  /// Deletes the custom template from the database.
  /// - Returns: `true` if deletion succeeded, `false` otherwise.
  public func deleteTemplate() async -> Bool {
    guard let templateId else { return false }
    do {
      try await checklistService.deleteCustomTemplate(id: templateId)
      Logger.checklist.info("Successfully deleted custom template: \(templateId.uuidString, privacy: .public)")
      return true
    } catch {
      Logger.checklist.error("Failed to delete custom template: \(String(reflecting: error), privacy: .public)")
      errorMessage = ChecklistSessionError.userMessage(for: error)
      return false
    }
  }

  // MARK: - Editing Actions

  /// Appends a new draft step to the checklist.
  /// - Returns: The newly created draft step.
  @discardableResult
  public func addItem(
    title: String = "",
    detail: String = ""
  ) -> ChecklistItemDraft {
    let item = ChecklistItemDraft(
      title: title,
      detail: detail
    )
    items.append(item)
    return item
  }

  /// Removes steps at the specified offsets.
  public func removeItems(atOffsets offsets: IndexSet) {
    items.remove(atOffsets: offsets)
  }

  /// Moves steps from source offsets to destination index.
  public func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
    items.move(fromOffsets: source, toOffset: destination)
  }

  /// Moves an item at the given index up by one position if possible.
  public func moveItemUp(at index: Int) {
    guard index > 0, index < items.count else { return }
    items.swapAt(index, index - 1)
  }

  /// Moves an item at the given index down by one position if possible.
  public func moveItemDown(at index: Int) {
    guard index >= 0, index < items.count - 1 else { return }
    items.swapAt(index, index + 1)
  }

  /// Moves the item with the given ID up by one position if possible.
  public func moveItemUp(id: UUID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    moveItemUp(at: index)
  }

  /// Moves the item with the given ID down by one position if possible.
  public func moveItemDown(id: UUID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    moveItemDown(at: index)
  }

  /// Persists the checklist template (inserting if new, updating if existing).
  /// - Returns: The saved `ChecklistTemplate` if successful, or `nil` on failure.
  public func save() async -> ChecklistTemplate? {
    guard isValid, !isSaving else {
      if let validation = validationErrorMessage {
        alertTitle = String(localized: "Incomplete Checklist")
        errorMessage = validation
      }
      return nil
    }
    isSaving = true
    defer { isSaving = false }
    errorMessage = nil

    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    let desc = trimmedDescription.isEmpty ? nil : trimmedDescription

    let validItems = items.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    do {
      let saved: ChecklistTemplate
      if let templateId {
        let serviceItems = validItems.map { item in
          let itemTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
          let itemDetail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
          return (
            id: Optional(item.id),
            title: itemTitle,
            detail: itemDetail.isEmpty ? nil : itemDetail
          )
        }
        saved = try await checklistService.updateCustomTemplate(
          id: templateId,
          title: trimmedTitle,
          description: desc,
          category: category,
          items: serviceItems
        )
        Logger.checklist.info("Successfully updated custom checklist template: \(saved.id.uuidString, privacy: .public)")
      } else {
        let serviceItems = validItems.map { item in
          let itemTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
          let itemDetail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
          return (
            title: itemTitle,
            detail: itemDetail.isEmpty ? nil : itemDetail
          )
        }
        saved = try await checklistService.createCustomTemplate(
          title: trimmedTitle,
          description: desc,
          category: category,
          items: serviceItems
        )
        Logger.checklist.info("Successfully created custom checklist template: \(saved.id.uuidString, privacy: .public)")
      }

      self.template = saved
      self.templateId = saved.id
      populate(from: saved)
      self.isEditable = false
      return saved
    } catch {
      Logger.checklist.error("Failed to save checklist template: \(String(reflecting: error), privacy: .public)")
      errorMessage = ChecklistSessionError.userMessage(for: error)
      return nil
    }
  }
}
