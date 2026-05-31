//
//  ActiveTrackViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

struct AnyLocalizedError: LocalizedError {
  let errorDescription: String?
}

@Observable
@MainActor
public final class ActiveTrackViewModel {
  public var recordingError: LocalizedError?
  public var recentlySavedSessionId: String?
  private let trackRecordingService: TrackRecordingService
  
  public init(trackRecordingService: TrackRecordingService) {
    self.trackRecordingService = trackRecordingService
  }
  
  public var isRecording: Bool {
    switch trackRecordingService.state {
    case .recording, .paused, .waitingForFix: return true
    case .idle, .saving: return false
    }
  }
  
  public var isSaving: Bool {
    trackRecordingService.state == .saving
  }
  
  public var state: TrackRecordingService.RecordingState {
    trackRecordingService.state
  }
  
  public var sessionTotalDistanceOverGround: Measurement<UnitLength>? {
    trackRecordingService.telemetry.totalDistanceOverGround
  }
  
  public func activeSessionDuration() -> Duration? {
    trackRecordingService.activeSessionDuration()
  }
  
  public func toggleRecording() {
    Task { [weak self] in
      guard let self else { return }
      do {
        if let sessionId = try await trackRecordingService.toggleRecording() {
          self.recentlySavedSessionId = sessionId
        }
      } catch {
        let localized = error as? LocalizedError ?? AnyLocalizedError(errorDescription: error.localizedDescription)
        self.recordingError = localized
        Logger.tracking.error("Failed to toggle recording: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}
