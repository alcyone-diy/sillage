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

@MainActor
@Observable
final class TrackListViewModel {
  var sessions: [TrackSession] = []
  
  init() {}
  
  func observe(trackService: TrackService) async {
    do {
      for try await newSessions in trackService.observeTrackSessions() {
        self.sessions = newSessions
      }
    } catch is CancellationError {
      Logger.database.debug("Track sessions observation cancelled.")
    } catch {
      Logger.database.error("Failed to observe track sessions: \(error, privacy: .public)")
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
    if let duration = session.duration {
      components.append(duration.marineFormatted)
    }
    if session.name != nil {
      components.append(session.startTime.formatted(date: .abbreviated, time: .shortened))
    }
    return components.isEmpty ? nil : components.joined(separator: " • ")
  }
}
