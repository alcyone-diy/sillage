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

  /// Destination for the active checklist modal presentation.
  public enum Destination: Identifiable, Equatable, Sendable {
    case single(ChecklistSession)
    case list

    public var id: String {
      switch self {
      case .single(let session):
        return session.id.uuidString
      case .list:
        return "active_checklists_list"
      }
    }
  }

  /// Current destination presented in a dedicated sheet.
  public var destination: Destination?

  public init() {}

  /// Handles tap on the active checklist button:
  /// - If exactly 1 checklist is in progress, opens that checklist directly.
  /// - If more than 1 checklist is in progress, opens the list of active checklists.
  public func openActiveChecklists() {
    if let single = singleActiveSession {
      destination = .single(single)
    } else if activeSessions.count > 1 {
      destination = .list
    }
  }

  /// Selects a specific checklist session to present in the modal.
  public func selectSession(_ session: ChecklistSession) {
    destination = .single(session)
  }

  /// Opens the single active session if exactly one is in progress.
  public func openSingleActiveSession() {
    guard let session = singleActiveSession else { return }
    destination = .single(session)
  }

  /// Dismisses the currently presented destination.
  public func dismiss() {
    destination = nil
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
          self.destination = nil
        } else if case .single(let current) = self.destination, !inProgressSessions.contains(where: { $0.id == current.id }) {
          self.destination = nil
        }
      }
    } catch {
      if !Task.isCancelled {
        Logger.checklist.error("Failed to observe active checklist sessions: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}
