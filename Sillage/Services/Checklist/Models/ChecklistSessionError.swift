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
///
/// - `errorDescription` is user-facing: localized, free of identifiers and architecture jargon.
/// - `debugDescription` carries technical details for logs (use `String(reflecting: error)`).
public enum ChecklistSessionError: Error, Sendable, LocalizedError, CustomDebugStringConvertible, Equatable {
  case templateNotFound(UUID)
  case sessionNotFound(UUID)
  case sessionAlreadyFinished(UUID)
  case itemNotFound(UUID)
  case templateHasExistingSessions(UUID)
  case databaseInconsistency(String)
  case databaseFailure(String)

  public var errorDescription: String? {
    switch self {
    case .templateNotFound:
      return String(localized: "This checklist no longer exists.")
    case .sessionNotFound:
      return String(localized: "This checklist is no longer available.")
    case .sessionAlreadyFinished:
      return String(localized: "This checklist is already finished.")
    case .itemNotFound:
      return String(localized: "This step no longer exists in the checklist.")
    case .templateHasExistingSessions:
      return String(localized: "This checklist cannot be deleted because it has log entries.")
    case .databaseInconsistency, .databaseFailure:
      return Self.storageFailureMessage
    }
  }

  public var debugDescription: String {
    switch self {
    case .templateNotFound(let id):
      return "Checklist template '\(id)' not found."
    case .sessionNotFound(let id):
      return "Checklist session '\(id)' not found."
    case .sessionAlreadyFinished(let id):
      return "Checklist session '\(id)' is already finished."
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

  /// Generic message for storage failures, never exposing raw database errors to the mariner.
  private static var storageFailureMessage: String {
    String(localized: "A storage error occurred. Please try again.")
  }

  /// Maps any error thrown by the checklist service to a mariner-facing message.
  /// Untyped errors (e.g. raw GRDB errors) fall back to the generic storage message.
  public static func userMessage(for error: any Error) -> String {
    (error as? ChecklistSessionError)?.errorDescription ?? storageFailureMessage
  }
}
