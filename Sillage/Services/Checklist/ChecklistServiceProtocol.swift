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

/// Public contract defining operations on maritime checklist templates and execution sessions.
public protocol ChecklistServiceProtocol: Sendable {
  // MARK: - Templates

  /// Fetches all available checklist templates ordered by sort position.
  func fetchTemplates() async throws -> [ChecklistTemplate]

  /// Fetches a specific template by its identifier.
  func fetchTemplate(id: UUID) async throws -> ChecklistTemplate?

  /// Creates a custom user-defined checklist template.
  func createCustomTemplate(
    title: String,
    description: String?,
    category: ChecklistCategory,
    items: [(title: String, detail: String?, isMandatory: Bool)]
  ) async throws -> ChecklistTemplate

  /// Deletes a custom template if no execution records are attached.
  func deleteCustomTemplate(id: UUID) async throws

  // MARK: - Executions (Get-or-Create pattern)

  /// Starts a new checklist execution or transparently returns the active one if already in progress.
  func startExecution(templateId: UUID) async throws(ChecklistExecutionError) -> ChecklistExecution

  /// Fetches the currently active in-progress execution for a given template, if any.
  func fetchActiveExecution(for templateId: UUID) async throws -> ChecklistExecution?

  /// Fetches an execution by its identifier.
  func fetchExecution(id: UUID) async throws -> ChecklistExecution?

  /// Fetches recent executions up to the specified limit.
  func fetchRecentExecutions(limit: Int) async throws -> [ChecklistExecution]

  /// Sets the checked state of a specific item idempotently with optional GPS coordinate auditing.
  func setItemChecked(
    executionId: UUID,
    itemId: UUID,
    isChecked: Bool,
    coordinate: CLLocationCoordinate2D?
  ) async throws(ChecklistExecutionError) -> ChecklistExecution

  /// Resets an active execution, clearing checked states and coordinates.
  func resetExecution(executionId: UUID) async throws(ChecklistExecutionError) -> ChecklistExecution

  /// Marks an in-progress execution as completed, ensuring all mandatory items are satisfied.
  func completeExecution(executionId: UUID, notes: String?) async throws(ChecklistExecutionError) -> ChecklistExecution

  /// Abandons an in-progress execution without marking it completed.
  func abandonExecution(executionId: UUID) async throws(ChecklistExecutionError) -> ChecklistExecution

  /// Seeds default system checklists if not present in the database.
  func seedDefaultTemplatesIfNeeded() async throws

  // MARK: - Reactive Observation

  /// Observes all currently active in-progress checklist sessions in real-time.
  func observeActiveExecutions() -> AsyncThrowingStream<[ChecklistExecution], any Error>
}
