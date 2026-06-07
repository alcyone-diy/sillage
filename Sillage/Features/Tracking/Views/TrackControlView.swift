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
  @Environment(AppViewModel.self) private var appViewModel
  
  @Environment(ActiveTrackViewModel.self) private var activeTrackViewModel
  
  var body: some View {
    @Bindable var bindableActiveTrackViewModel = activeTrackViewModel
    
    Section(header: Text("Active Track")) {
      HStack {
        Text("Recording Status")
        Spacer()
        Toggle("", isOn: Binding(
          get: { activeTrackViewModel.isRecording },
          set: { _ in activeTrackViewModel.toggleRecording() }
        ))
        .labelsHidden()
        .disabled(activeTrackViewModel.isSaving)
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
      
      // Telemetry: Distance
      HStack {
        Text("Distance")
        Spacer()
        
        if let distance = activeTrackViewModel.sessionTotalDistanceOverGround {
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
    .alert(
      "Track Recording",
      isPresented: Binding(
        get: { activeTrackViewModel.recordingError != nil },
        set: { if !$0 { activeTrackViewModel.recordingError = nil } }
      ),
      presenting: activeTrackViewModel.recordingError
    ) { _ in
      Button("OK", role: .cancel) { }
    } message: { error in
      Text(error.errorDescription ?? "")
    }
  }
  
  @ViewBuilder
  private var durationValueView: some View {
    switch activeTrackViewModel.state {
    case .recording, .waitingForFix:
      TimelineView(.periodic(from: .now, by: 1.0)) { context in
        let liveDuration = activeTrackViewModel.activeSessionDuration() ?? .seconds(0)
        Text(liveDuration, format: .time(pattern: .hourMinuteSecond))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    case .idle, .paused, .saving:
      let staticDuration = activeTrackViewModel.activeSessionDuration()
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
