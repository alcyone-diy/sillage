//
//  ChecklistSessionServiceProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Public contract defining checklist session lifecycle operations and real-time reactive observations.
@MainActor
public protocol ChecklistSessionServiceProtocol: Sendable {
  // MARK: - Sessions (Get-or-Create pattern)

  /// Starts a new checklist session or transparently returns the active one if already in progress.
  func startSession(templateId: UUID) async throws(ChecklistError) -> ChecklistSession

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
  ) async throws(ChecklistError) -> ChecklistSession

  /// Deletes the specified session and all its associated items.
  func deleteSession(sessionId: UUID) async throws(ChecklistError)

  /// Marks an in-progress session as completed.
  func completeSession(sessionId: UUID, notes: String?) async throws(ChecklistError) -> ChecklistSession

  /// Abandons an in-progress session without marking it completed.
  func abandonSession(sessionId: UUID) async throws(ChecklistError) -> ChecklistSession

  /// Fetches the latest completion date for a checklist template, if any.
  func fetchLatestCompletionDate(for templateId: UUID) async throws -> Date?

  // MARK: - Reactive Observation

  /// Observes active in-progress and recently completed checklist sessions in real-time.
  func observeSessions() -> AsyncThrowingStream<[ChecklistSession], any Error>

  /// Observes all currently active in-progress checklist sessions in real-time.
  func observeActiveSessions() -> AsyncThrowingStream<[ChecklistSession], any Error>

  /// Observes the latest completion date for each checklist template in real-time.
  func observeCompletedSessions() -> AsyncThrowingStream<[UUID: Date], any Error>
}

extension ChecklistSessionServiceProtocol {
  /// Sets the checked state of a specific item without a GPS audit coordinate.
  public func setItemChecked(
    sessionId: UUID,
    itemId: UUID,
    isChecked: Bool
  ) async throws(ChecklistError) -> ChecklistSession {
    try await setItemChecked(
      sessionId: sessionId,
      itemId: itemId,
      isChecked: isChecked,
      coordinate: nil
    )
  }

  /// Marks an in-progress session as completed without notes.
  public func completeSession(sessionId: UUID) async throws(ChecklistError) -> ChecklistSession {
    try await completeSession(sessionId: sessionId, notes: nil)
  }
}
