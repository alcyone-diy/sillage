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
import Observation
import OSLog

/// A view model managing the read-only presentation and session launching for a checklist template.
@MainActor
@Observable
public final class ChecklistTemplateDetailViewModel {
  public let templateId: UUID
  private let checklistService: any ChecklistServiceProtocol

  public private(set) var template: ChecklistTemplate?
  public private(set) var activeSession: ChecklistSession?
  public private(set) var isLoading: Bool = false
  public var errorMessage: String?

  public var title: String {
    template?.title ?? ""
  }

  public var description: String? {
    template?.description
  }

  public var category: ChecklistCategory? {
    template?.category
  }

  public var items: [ChecklistTemplateItem] {
    template?.items.sorted { $0.sortOrder < $1.sortOrder } ?? []
  }

  public var hasActiveSession: Bool {
    activeSession != nil && activeSession?.status == .inProgress && (activeSession?.completedCount ?? 0) > 0
  }

  public init(
    templateId: UUID,
    checklistService: any ChecklistServiceProtocol
  ) {
    self.templateId = templateId
    self.checklistService = checklistService
  }

  /// Loads the checklist template and any currently active session.
  public func load() async {
    isLoading = true
    defer { isLoading = false }
    errorMessage = nil

    do {
      self.template = try await checklistService.fetchTemplate(id: templateId)
      self.activeSession = try await checklistService.fetchActiveSession(for: templateId)
    } catch {
      Logger.checklist.error("Failed to load checklist template \(self.templateId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }

  /// Starts a new session or transparently resumes the active session for this template.
  /// - Returns: The UUID of the session, or `nil` on failure.
  public func startOrResumeSession() async -> UUID? {
    do {
      let session = try await checklistService.startSession(templateId: templateId)
      self.activeSession = session
      return session.id
    } catch {
      Logger.checklist.error("Failed to start or resume checklist session: \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
      return nil
    }
  }

  /// Deletes the custom template from the database.
  /// - Returns: `true` if deletion succeeded, `false` otherwise.
  public func deleteTemplate() async -> Bool {
    do {
      try await checklistService.deleteCustomTemplate(id: templateId)
      Logger.checklist.info("Successfully deleted custom template: \(self.templateId.uuidString, privacy: .public)")
      return true
    } catch {
      Logger.checklist.error("Failed to delete custom template: \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
      return false
    }
  }
}
