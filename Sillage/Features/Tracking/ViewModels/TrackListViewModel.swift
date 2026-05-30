//
//  TrackListViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import Observation
import OSLog

enum TrackError: LocalizedError {
  case deletionFailed
  
  var errorDescription: String? {
    switch self {
    case .deletionFailed:
      return String(localized: "Failed to delete track. Please try again.")
    }
  }
}

@MainActor
@Observable
final class TrackListViewModel {
  var sessions: [TrackSession] = []
  var activeError: TrackError?
  
  init() {}
  
  func observe(trackService: TrackService) async {
    do {
      for try await newSessions in trackService.observeTrackSessions() {
        if Task.isCancelled { break }
        self.sessions = newSessions
      }
    } catch is CancellationError {
      Logger.tracking.debug("Track sessions observation cancelled.")
    } catch {
      Logger.tracking.error("Failed to observe track sessions: \(error, privacy: .public)")
    }
  }
  
  func subtitle(for session: TrackSession) -> String? {
    var components: [String] = []
    if let distance = session.totalDistance {
      let distStr = distance.converted(to: .nauticalMiles).formatted(
        .measurement(
          width: .abbreviated,
          usage: .asProvided,
          numberFormatStyle: .number.precision(.fractionLength(2))
        )
      )
      components.append(distStr)
    }
    if let duration = session.totalDuration {
      components.append(duration.marineFormatted)
    }
    if session.name != nil {
      components.append(session.startTime.formatted(date: .abbreviated, time: .shortened))
    }
    return components.isEmpty ? nil : components.joined(separator: " • ")
  }
  
  func deleteSession(_ session: TrackSession, trackService: TrackService, trackRecordingService: TrackRecordingService) {
    guard !trackRecordingService.isSessionActive(session.id) else {
      Logger.tracking.fault("Illegal attempt to delete an active track: \(session.id, privacy: .public)")
      return
    }
    
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await trackService.deleteSession(id: session.id)
      } catch is CancellationError {
        Logger.tracking.debug("Track deletion cancelled for \(session.id, privacy: .public)")
      } catch {
        Logger.tracking.error("Failed to delete track session \(session.id, privacy: .public): \(error, privacy: .public)")
        self.activeError = .deletionFailed
      }
    }
  }
}
