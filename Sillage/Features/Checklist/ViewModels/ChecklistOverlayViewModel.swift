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

  public init() {}

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
      }
    } catch {
      if !Task.isCancelled {
        Logger.checklist.error("Failed to observe active checklist sessions: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}
