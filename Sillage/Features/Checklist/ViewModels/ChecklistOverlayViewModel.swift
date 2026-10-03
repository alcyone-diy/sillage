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

/// Manages the presentation state and business filtering for active checklists in the main overlay.
@Observable
@MainActor
public final class ChecklistOverlayViewModel {
  /// Uncompleted checklist sessions with active progress (`completedCount > 0`).
  public private(set) var activeSessions: [ChecklistSession] = []

  /// Whether any active checklist session is currently in progress.
  public var hasActiveChecklists: Bool {
    !activeSessions.isEmpty
  }

  /// Single active session if exactly one checklist is in progress.
  public var singleActiveSession: ChecklistSession? {
    activeSessions.count == 1 ? activeSessions.first : nil
  }

  /// Total number of completed steps across all in-progress checklist sessions.
  public var completedStepsCount: Int {
    activeSessions.reduce(0) { $0 + $1.completedCount }
  }

  /// Total number of steps across all in-progress checklist sessions.
  public var totalStepsCount: Int {
    activeSessions.reduce(0) { $0 + $1.totalCount }
  }

  /// Ratio of completed steps over total steps across in-progress checklist sessions (between 0.0 and 1.0).
  public var progressRatio: Double {
    guard totalStepsCount > 0 else { return 0.0 }
    return Double(completedStepsCount) / Double(totalStepsCount)
  }

  /// Whether the dedicated active checklist sheet is presented.
  public var isSheetPresented: Bool = false

  /// The navigation path stack for checklist sessions within the sheet.
  public var navigationPath: [UUID] = []

  public init() {}

  /// Handles tap on the active checklist button:
  /// - If exactly 1 checklist is in progress, opens that checklist directly.
  /// - If more than 1 checklist is in progress, opens the list of active checklists.
  public func openActiveChecklists() {
    isSheetPresented = true
    if let single = singleActiveSession {
      navigationPath = [single.id]
    } else {
      navigationPath = []
    }
  }

  /// Selects a specific checklist session to present in the modal stack.
  public func selectSession(_ session: ChecklistSession) {
    if !navigationPath.contains(session.id) {
      navigationPath.append(session.id)
    }
  }

  /// Dismisses the active checklist sheet and clears the navigation stack.
  public func dismiss() {
    isSheetPresented = false
    navigationPath.removeAll()
  }

  /// Observes active checklist sessions continuously using structured concurrency.
  /// Cancellation is handled automatically by the caller's asynchronous context (e.g. SwiftUI `.task`).
  public func observe(service: any ChecklistServiceProtocol) async {
    do {
      for try await sessions in service.observeActiveSessions() {
        if Task.isCancelled { break }
        let inProgressSessions = sessions.filter {
          $0.status == .inProgress && $0.completedCount > 0
        }
        self.activeSessions = inProgressSessions
        if inProgressSessions.isEmpty {
          self.isSheetPresented = false
          self.navigationPath.removeAll()
        } else {
          self.navigationPath = self.navigationPath.filter { id in
            inProgressSessions.contains(where: { $0.id == id })
          }
        }
      }
    } catch {
      if !Task.isCancelled {
        Logger.checklist.error("Failed to observe active checklist sessions: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}
