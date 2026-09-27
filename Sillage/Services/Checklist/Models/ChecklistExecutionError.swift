//
//  ChecklistExecutionError.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Specific domain errors related to checklist lifecycle and database operations.
public enum ChecklistExecutionError: Error, Sendable, LocalizedError {
  case templateNotFound(UUID)
  case executionNotFound(UUID)
  case executionAlreadyFinished(UUID)
  case itemNotFound(UUID)
  case mandatoryItemsRemaining(remainingCount: Int)
  case templateHasExistingExecutions(UUID)
  case databaseInconsistency(String)
  case databaseFailure(String)

  public var errorDescription: String? {
    switch self {
    case .templateNotFound(let id):
      return "Checklist template '\(id)' not found."
    case .executionNotFound(let id):
      return "Checklist execution '\(id)' not found."
    case .executionAlreadyFinished(let id):
      return "Checklist execution '\(id)' is already finished or archived."
    case .itemNotFound(let id):
      return "Checklist item '\(id)' not found in execution."
    case .mandatoryItemsRemaining(let count):
      return "\(count) mandatory checklist item(s) must be checked before completing."
    case .templateHasExistingExecutions(let id):
      return "Cannot delete template '\(id)' because it has associated historical executions."
    case .databaseInconsistency(let reason):
      return "Critical database inconsistency: \(reason)"
    case .databaseFailure(let msg):
      return "Database operation failure: \(msg)"
    }
  }
}
