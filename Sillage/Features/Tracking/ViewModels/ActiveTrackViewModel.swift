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

@Observable
@MainActor
public final class ActiveTrackViewModel {
  public var recordingError: TrackRecordingStopError?
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
  
  public var sessionDistance: Measurement<UnitLength>? {
    trackRecordingService.sessionDistance
  }
  
  public func activeSessionDuration(at date: Date) -> Duration? {
    trackRecordingService.activeSessionDuration(at: date)
  }
  
  public func toggleRecording() {
    let result = trackRecordingService.toggleRecording()
    if case .stopped(let stopResult) = result {
      self.recordingError = TrackRecordingStopError(from: stopResult)
    }
  }
}
