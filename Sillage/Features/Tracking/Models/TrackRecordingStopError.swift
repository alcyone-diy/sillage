//
//  TrackRecordingStopError.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public enum TrackRecordingStopError: LocalizedError {
  case abortedNoFix
  case noActiveRecording
  
  public init?(from result: TrackRecordingService.StopRecordingResult) {
    switch result {
    case .abortedNoFix: self = .abortedNoFix
    case .noActiveRecording: self = .noActiveRecording
    case .savedAsync: return nil
    }
  }
  
  public var errorDescription: String? {
    switch self {
    case .abortedNoFix:
      return String(localized: "Recording aborted. No GPS fix was obtained.")
    case .noActiveRecording:
      return String(localized: "No active recording to stop.")
    }
  }
}
