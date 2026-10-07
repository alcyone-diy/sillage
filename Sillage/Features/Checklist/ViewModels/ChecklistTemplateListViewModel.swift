//
//  ChecklistTemplateListViewModel.swift
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

/// A view model managing the presentation of available checklist templates.
@MainActor
@Observable
public final class ChecklistTemplateListViewModel {
  private let checklistService: any ChecklistServiceProtocol

  public private(set) var templates: [ChecklistTemplate] = []
  public private(set) var activeSessions: [ChecklistSession] = []
  public private(set) var latestCompletionDates: [UUID: Date] = [:]
  public private(set) var isLoading: Bool = false
  public var errorMessage: String?

  /// Templates grouped by category in defined order.
  public var groupedTemplates: [(category: ChecklistCategory, templates: [ChecklistTemplate])] {
    let grouped = Dictionary(grouping: templates, by: \.category)
    return ChecklistCategory.allCases.compactMap { category in
      guard let list = grouped[category], !list.isEmpty else { return nil }
      return (category: category, templates: list)
    }
  }

  public init(checklistService: any ChecklistServiceProtocol) {
    self.checklistService = checklistService
  }

  /// Loads available checklist templates from the database, sorted alphabetically.
  public func loadTemplates() async {
    isLoading = true
    defer { isLoading = false }
    errorMessage = nil

    do {
      let fetched = try await checklistService.fetchTemplates()
      templates = fetched.sorted(by: ChecklistTemplate.standardComparator)
    } catch {
      Logger.checklist.error("Failed to load checklist templates: \(String(reflecting: error), privacy: .public)")
      errorMessage = ChecklistSessionError.userMessage(for: error)
    }
  }

  /// Observes active in-progress checklist sessions.
  public func observeActiveSessions() async {
    do {
      for try await sessions in checklistService.observeActiveSessions() {
        if Task.isCancelled { break }
        self.activeSessions = sessions
      }
    } catch {
      if !Task.isCancelled {
        Logger.checklist.error("Error observing active sessions: \(String(reflecting: error), privacy: .public)")
      }
    }
  }

  /// Returns whether a template has an active in-progress session with progress.
  public func hasActiveSession(for templateId: UUID) -> Bool {
    activeSessions.contains {
      $0.templateId == templateId &&
      $0.status == .inProgress &&
      $0.completedCount > 0
    }
  }

  /// Returns the active session for a template if one exists with progress.
  public func activeSession(for templateId: UUID) -> ChecklistSession? {
    activeSessions.first {
      $0.templateId == templateId &&
      $0.status == .inProgress &&
      $0.completedCount > 0
    }
  }

  /// Starts or resumes a session for the specified template.
  /// - Returns: The active `ChecklistSession`, or `nil` on failure.
  public func startOrResumeSession(for templateId: UUID) async -> ChecklistSession? {
    do {
      let session = try await checklistService.startSession(templateId: templateId)
      return session
    } catch {
      Logger.checklist.error("Failed to start or resume session for template \(templateId.uuidString, privacy: .public): \(String(reflecting: error), privacy: .public)")
      errorMessage = ChecklistSessionError.userMessage(for: error)
      return nil
    }
  }

  /// Observes latest completion dates for checklist templates.
  public func observeCompletedSessions() async {
    do {
      for try await dates in checklistService.observeCompletedSessions() {
        if Task.isCancelled { break }
        self.latestCompletionDates = dates
      }
    } catch {
      if !Task.isCancelled {
        Logger.checklist.error("Error observing completed sessions: \(String(reflecting: error), privacy: .public)")
      }
    }
  }

  /// Returns the latest completion date for a template, if any exists.
  public func latestCompletionDate(for templateId: UUID) -> Date? {
    latestCompletionDates[templateId]
  }

  /// Deletes a custom checklist template.
  public func deleteTemplate(id: UUID) async -> Bool {
    do {
      try await checklistService.deleteCustomTemplate(id: id)
      await loadTemplates()
      return true
    } catch {
      Logger.checklist.error("Failed to delete custom template \(id.uuidString, privacy: .public): \(String(reflecting: error), privacy: .public)")
      errorMessage = ChecklistSessionError.userMessage(for: error)
      return false
    }
  }
}

extension ChecklistTemplate {
  /// Compares two templates primarily by manual sort order, falling back to alphabetical sorting by title.
  public static func standardComparator(_ lhs: ChecklistTemplate, _ rhs: ChecklistTemplate) -> Bool {
    if lhs.sortOrder != rhs.sortOrder {
      return lhs.sortOrder < rhs.sortOrder
    }
    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }
}
