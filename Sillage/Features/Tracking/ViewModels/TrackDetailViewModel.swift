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

  var pointsCount: Int?
  var segmentCount: Int?
  var maxSpeed: Measurement<UnitSpeed>?

  var isEditing: Bool = false
  var isSaving: Bool = false
  var errorMessage: String?

  private let sessionId: String

  init(sessionId: String) {
    self.sessionId = sessionId
  }

  func load(trackService: TrackService) async {
    // 1. Fetch stats asynchronously
    do {
      let stats = try await trackService.fetchTrackStats(id: sessionId)
      self.pointsCount = stats.pointsCount
      self.segmentCount = stats.segmentCount
      self.maxSpeed = stats.maxSpeed
    } catch {
      Logger.database.error("Failed to fetch track stats for \(self.sessionId, privacy: .public): \(error, privacy: .public)")
    }

    // 2. Observe session updates reactively
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

  func saveChanges(trackService: TrackService) async {
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
        description: finalDesc
      )
      isEditing = false
    } catch {
      Logger.database.error("Failed to update track session \(self.sessionId, privacy: .public): \(error, privacy: .public)")
      errorMessage = "Failed to save changes. Please try again."
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
}
