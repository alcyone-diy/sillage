//
//  TrackDetailViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class TrackDetailViewModel {
  var session: TrackSession?
  var name: String = ""
  var description: String = ""

  var isEditing: Bool = false
  var isSaving: Bool = false
  var errorMessage: String?

  let sessionId: String
  private let trackService: TrackService
  private let trackRecordingService: TrackRecordingService

  init(
    sessionId: String,
    trackService: TrackService,
    trackRecordingService: TrackRecordingService
  ) {
    self.sessionId = sessionId
    self.trackService = trackService
    self.trackRecordingService = trackRecordingService
  }

  /// Indique si la suppression est autorisée (masque/désactive le bouton dans l'UI)
  var canDelete: Bool {
    return !trackRecordingService.isSessionActive(sessionId)
  }

  func load() async {
    // Observe session updates reactively
    do {
      for try await updatedSession in trackService.observeTrackSession(id: sessionId) {
        self.session = updatedSession
        if let updatedSession, !isEditing {
          self.name = updatedSession.name ?? ""
          self.description = updatedSession.description ?? ""
        }
      }
    } catch is CancellationError {
      Logger.database.debug("Track session observation cancelled for \(self.sessionId, privacy: .public)")
    } catch {
      Logger.database.error("Failed to observe track session \(self.sessionId, privacy: .public): \(error, privacy: .public)")
    }
  }

  func saveChanges() async {
    guard let session else { return }
    isSaving = true
    errorMessage = nil

    do {
      let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
      let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)

      let finalName = trimmedName.isEmpty ? nil : trimmedName
      let finalDesc = trimmedDesc.isEmpty ? nil : trimmedDesc

      try await trackService.updateSession(
        id: session.id,
        name: finalName,
        description: finalDesc,
        startLocation: session.startLocation,
        endLocation: session.endLocation
      )
      isEditing = false
    } catch {
      Logger.database.error("Failed to update track session \(self.sessionId, privacy: .public): \(error, privacy: .public)")
      errorMessage = String(localized: "Failed to save changes. Please try again.")
    }

    isSaving = false
  }

  func cancelEditing() {
    isEditing = false
    if let session {
      name = session.name ?? ""
      description = session.description ?? ""
    }
  }

  /// Deletes the track session from the database.
  func deleteSession() async throws {
    // Garde-fou silencieux en cas d'appel abusif
    guard canDelete else {
      let error = TrackDeletionError.activeSession
      errorMessage = error.localizedDescription
      Logger.database.warning("Attempted to delete active session: \(self.sessionId, privacy: .public)")
      throw error
    }

    errorMessage = nil
    do {
      try await trackService.deleteSession(id: sessionId)
    } catch {
      Logger.database.error("Failed to delete track session \(self.sessionId, privacy: .public): \(error, privacy: .public)")
      errorMessage = String(localized: "Failed to delete track. Please try again.")
      throw error
    }
  }
}

public enum TrackDeletionError: LocalizedError {
  case activeSession

  public var errorDescription: String? {
    switch self {
    case .activeSession:
      return String(localized: "Cannot delete a track while it is actively recording.")
    }
  }
}
