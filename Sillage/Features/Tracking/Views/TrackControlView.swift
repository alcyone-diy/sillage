//
//  TrackControlView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation

@MainActor
struct TrackControlView: View {
  @Environment(TrackRecordingService.self) private var trackRecordingService
  @Environment(AppViewModel.self) private var appViewModel
  
  var body: some View {
    Section(header: Text("Active Track")) {
      HStack {
        Text("Recording Status")
        Spacer()
        Toggle("", isOn: Binding(
          get: { 
            switch trackRecordingService.state {
            case .recording, .paused, .waitingForFix: return true
            case .idle, .saving: return false
            }
          },
          set: { _ in trackRecordingService.toggleRecording() }
        ))
        .labelsHidden()
      }
      .marineListCell()
      .marineFont(.body)
      
      HStack {
        Text("Duration")
        Spacer()
        durationValueView
      }
      .marineListCell()
      .marineFont(.body)
      
      // Télémétrie : Distance
      HStack {
        Text("Distance")
        Spacer()
        
        if let distance = trackRecordingService.sessionDistance {
          Text(distance.converted(to: .nauticalMiles).formatted(
            .measurement(width: .abbreviated,
                         usage: .asProvided,
                         numberFormatStyle: .number.precision(.fractionLength(2)))
          ))
          .monospacedDigit()
          .foregroundStyle(.secondary)
        } else {
          Text("--")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
      .marineListCell()
      .marineFont(.body)
    }
  }
  
  @ViewBuilder
  private var durationValueView: some View {
    switch trackRecordingService.state {
    case .recording, .waitingForFix:
      TimelineView(.periodic(from: .now, by: 1.0)) { context in
        let liveDuration = trackRecordingService.activeSessionDuration(at: context.date) ?? .seconds(0)
        Text(liveDuration, format: .time(pattern: .hourMinuteSecond))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    case .idle, .paused, .saving:
      let staticDuration = trackRecordingService.activeSessionDuration(at: Date())
      if let duration = staticDuration {
        Text(duration, format: .time(pattern: .hourMinuteSecond))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      } else {
        Text("--:--:--")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
  }
}
