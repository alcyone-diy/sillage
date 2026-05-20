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
}
