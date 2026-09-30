//
//  ChecklistSessionError.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Specific domain errors related to checklist lifecycle and database operations.
public enum ChecklistSessionError: Error, Sendable, LocalizedError, Equatable {
  case templateNotFound(UUID)
  case sessionNotFound(UUID)
  case sessionAlreadyFinished(UUID)
  case itemNotFound(UUID)
  case templateHasExistingSessions(UUID)
  case databaseInconsistency(String)
  case databaseFailure(String)

  public var errorDescription: String? {
    switch self {
    case .templateNotFound(let id):
      return "Checklist template '\(id)' not found."
    case .sessionNotFound(let id):
      return "Checklist session '\(id)' not found."
    case .sessionAlreadyFinished(let id):
      return "Checklist session '\(id)' is already finished or archived."
    case .itemNotFound(let id):
      return "Checklist item '\(id)' not found in session."
    case .templateHasExistingSessions(let id):
      return "Cannot delete template '\(id)' because it has associated historical sessions."
    case .databaseInconsistency(let reason):
      return "Critical database inconsistency: \(reason)"
    case .databaseFailure(let msg):
      return "Database operation failure: \(msg)"
    }
  }
}
