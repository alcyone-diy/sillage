//
//  ChecklistOverlayViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

/// Scoped destination enum for navigating within the active checklist overlay stack.
public enum ChecklistOverlayDestination: Hashable, Sendable {
  /// Presents an active or completed checklist session.
  case session(ChecklistSessionPayload)
  case templateDetail(templateId: UUID, startEditable: Bool = true)
}

/// Manages the presentation state and observation for checklist sessions in the main overlay.
@Observable
@MainActor
public final class ChecklistOverlayViewModel {
  /// All tracked checklist sessions (both in-progress and completed).
  public private(set) var activeSessions: [ChecklistSession] = []

  /// Sessions that are currently in progress, sorted alphabetically by title.
  public var inProgressSessions: [ChecklistSession] {
    activeSessions
      .filter { $0.status == .inProgress }
      .sorted(by: ChecklistSession.inProgressAlphabeticalComparator)
  }

  /// Sessions that have been completed, sorted alphabetically by title.
  public var completedSessions: [ChecklistSession] {
    activeSessions
      .filter { $0.status == .completed }
      .sorted(by: ChecklistSession.completedAlphabeticalComparator)
  }

  /// In-progress sessions belonging to a specific category ID.
  public func inProgressSessions(for categoryId: String) -> [ChecklistSession] {
    inProgressSessions.filter { $0.categoryId == categoryId }
  }

  /// Completed sessions belonging to a specific category ID.
  public func completedSessions(for categoryId: String) -> [ChecklistSession] {
    completedSessions.filter { $0.categoryId == categoryId }
  }

  /// Whether any checklist session is currently in progress.
  /// When all checklists are completed (even if retained in activeSessions for 48h),
  /// the floating button must disappear from the main map overlay.
  public var hasActiveChecklists: Bool {
    !inProgressSessions.isEmpty
  }

  /// Single active session if exactly one checklist is currently in progress.
  public var singleActiveSession: ChecklistSession? {
    if inProgressSessions.count == 1 {
      return inProgressSessions.first
    }
    return nil
  }

  /// Total number of completed steps across all in-progress checklist sessions.
  public var completedStepsCount: Int {
    inProgressSessions.reduce(0) { $0 + $1.completedCount }
  }

  /// Total number of steps across all in-progress checklist sessions.
  public var totalStepsCount: Int {
    inProgressSessions.reduce(0) { $0 + $1.totalCount }
  }

  /// Ratio of completed steps over total steps across in-progress checklist sessions (between 0.0 and 1.0).
  public var progressRatio: Double {
    guard totalStepsCount > 0 else { return 0.0 }
    return Double(completedStepsCount) / Double(totalStepsCount)
  }

  /// Whether the dedicated active checklist sheet is presented.
  public var isSheetPresented: Bool = false

  /// The navigation path stack for checklist destinations within the sheet.
  public var navigationPath: [ChecklistOverlayDestination] = []

  public init() {}

  /// Handles tap on the active checklist button:
  /// - If exactly 1 checklist is in progress, opens that checklist directly.
  /// - If more than 1 checklist is in progress, opens the list of active checklists.
  public func openActiveChecklists() {
    isSheetPresented = true
    if inProgressSessions.count == 1, let single = inProgressSessions.first {
      navigationPath = [.session(ChecklistSessionPayload(id: single.id, snapshot: single))]
    } else {
      navigationPath = []
    }
  }

  /// Selects a specific checklist session to present in the modal stack.
  public func selectSession(_ session: ChecklistSession) {
    let destination = ChecklistOverlayDestination.session(ChecklistSessionPayload(id: session.id, snapshot: session))
    if !navigationPath.contains(destination) {
      navigationPath.append(destination)
    }
  }

  /// Dismisses the active checklist sheet and clears the navigation stack.
  public func dismiss() {
    isSheetPresented = false
    navigationPath.removeAll()
  }

  /// Observes checklist sessions continuously using structured concurrency.
  /// Cancellation is handled automatically by the caller's asynchronous context (e.g. SwiftUI `.task`).
  public func observe(service: any ChecklistServiceProtocol) async {
    do {
      for try await sessions in service.observeSessions() {
        if Task.isCancelled { break }
        self.activeSessions = sessions
      }
    } catch {
      if !Task.isCancelled {
        Logger.checklist.error("Failed to observe active checklist sessions: \(String(reflecting: error), privacy: .public)")
      }
    }
  }
}

extension ChecklistSession {
  /// Compares two in-progress sessions alphabetically by template title snapshot,
  /// falling back to started date (most recent first).
  public static func inProgressAlphabeticalComparator(_ lhs: ChecklistSession, _ rhs: ChecklistSession) -> Bool {
    let comparison = lhs.templateTitleSnapshot.localizedStandardCompare(rhs.templateTitleSnapshot)
    if comparison == .orderedSame {
      return lhs.startedAt > rhs.startedAt
    }
    return comparison == .orderedAscending
  }

  /// Compares two completed sessions alphabetically by template title snapshot,
  /// falling back to completion date (most recent first).
  public static func completedAlphabeticalComparator(_ lhs: ChecklistSession, _ rhs: ChecklistSession) -> Bool {
    let comparison = lhs.templateTitleSnapshot.localizedStandardCompare(rhs.templateTitleSnapshot)
    if comparison == .orderedSame {
      let lhsDate = lhs.completedAt ?? lhs.startedAt
      let rhsDate = rhs.completedAt ?? rhs.startedAt
      return lhsDate > rhsDate
    }
    return comparison == .orderedAscending
  }
}
