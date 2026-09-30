//
//  ChecklistServiceProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Public contract defining operations on maritime checklist templates and sessions.
public protocol ChecklistServiceProtocol: Sendable {
  // MARK: - Templates

  /// Fetches all available checklist templates ordered by sort position.
  func fetchTemplates() async throws -> [ChecklistTemplate]

  /// Fetches a specific template by its identifier.
  func fetchTemplate(id: UUID) async throws -> ChecklistTemplate?

  /// Creates a checklist template.
  func createTemplate(
    title: String,
    description: String?,
    category: ChecklistCategory,
    items: [(title: String, detail: String?)]
  ) async throws -> ChecklistTemplate

  /// Updates an existing checklist template and its items.
  func updateTemplate(
    id: UUID,
    title: String,
    description: String?,
    category: ChecklistCategory,
    items: [(id: UUID?, title: String, detail: String?)]
  ) async throws -> ChecklistTemplate

  /// Deletes a template and its associated sessions.
  func deleteTemplate(id: UUID) async throws

  /// Creates a custom user-defined checklist template.
  func createCustomTemplate(
    title: String,
    description: String?,
    category: ChecklistCategory,
    items: [(title: String, detail: String?)]
  ) async throws -> ChecklistTemplate

  /// Updates an existing custom checklist template and its items.
  func updateCustomTemplate(
    id: UUID,
    title: String,
    description: String?,
    category: ChecklistCategory,
    items: [(id: UUID?, title: String, detail: String?)]
  ) async throws -> ChecklistTemplate

  /// Deletes a custom template and its associated sessions.
  func deleteCustomTemplate(id: UUID) async throws

  // MARK: - Sessions (Get-or-Create pattern)

  /// Starts a new checklist session or transparently returns the active one if already in progress.
  func startSession(templateId: UUID) async throws(ChecklistSessionError) -> ChecklistSession

  /// Fetches the currently active in-progress session for a given template, if any.
  func fetchActiveSession(for templateId: UUID) async throws -> ChecklistSession?

  /// Fetches a session by its identifier.
  func fetchSession(id: UUID) async throws -> ChecklistSession?

  /// Fetches recent sessions up to the specified limit.
  func fetchRecentSessions(limit: Int) async throws -> [ChecklistSession]

  /// Sets the checked state of a specific item idempotently with optional GPS coordinate auditing.
  func setItemChecked(
    sessionId: UUID,
    itemId: UUID,
    isChecked: Bool,
    coordinate: CLLocationCoordinate2D?
  ) async throws(ChecklistSessionError) -> ChecklistSession

  /// Resets an active session, clearing checked states and coordinates.
  func resetSession(sessionId: UUID) async throws(ChecklistSessionError) -> ChecklistSession

  /// Marks an in-progress session as completed.
  func completeSession(sessionId: UUID, notes: String?) async throws(ChecklistSessionError) -> ChecklistSession

  /// Abandons an in-progress session without marking it completed.
  func abandonSession(sessionId: UUID) async throws(ChecklistSessionError) -> ChecklistSession

  /// Seeds default system checklists if not present in the database.
  func seedDefaultTemplatesIfNeeded() async throws

  // MARK: - Reactive Observation

  /// Observes all currently active in-progress checklist sessions in real-time.
  func observeActiveSessions() -> AsyncThrowingStream<[ChecklistSession], any Error>
}

extension ChecklistServiceProtocol {
  /// Updates an existing custom checklist template with simple item tuples.
  public func updateCustomTemplate(
    id: UUID,
    title: String,
    description: String?,
    category: ChecklistCategory,
    items: [(title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await updateCustomTemplate(
      id: id,
      title: title,
      description: description,
      category: category,
      items: items.map { (id: nil, title: $0.title, detail: $0.detail) }
    )
  }
}

