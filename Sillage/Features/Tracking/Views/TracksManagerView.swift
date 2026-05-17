//
//  TracksManagerView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct TracksManagerView: View {
  @Environment(TrackRecordingService.self) private var trackRecordingService
  @Environment(AppViewModel.self) private var appViewModel
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    @Bindable var bindableAppViewModel = appViewModel
    
    List {
      Section(header: Text("Active Trace")) {
        HStack {
          Text("Recording Status")
          Spacer()
          Toggle("", isOn: Binding(
            get: { trackRecordingService.isRecording },
            set: { _ in trackRecordingService.toggleRecording() }
          ))
            .labelsHidden()
        }
        .disabled(!appViewModel.isDatabaseReady)
        .marineListCell()
        .marineFont(.body)
        
        HStack {
          Text("Duration")
          Spacer()
          durationValueView
        }
        .marineListCell()
        .marineFont(.body)
        
        HStack {
          Text("Distance")
          Spacer()
          if let distance = trackRecordingService.sessionDistance {
            let nm = distance.converted(to: .nauticalMiles).value
            Text(String(format: "%.2f NM", nm))
              .monospacedDigit()
              .foregroundStyle(.secondary)
          } else {
            Text(String(format: "-- NM"))
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        }
        .marineListCell()
        .marineFont(.body)
        
      }
      
      Section(header: Text("Saved Traces")) {
        Text("Coming soon...")
          .foregroundStyle(.secondary)
          .marineListCell()
          .marineFont(.body)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(MarineTheme.Colors.panelBackground)
    .handleTrackRecordingErrors()
    .navigationTitle("Track Manager")
    .navigationBarTitleDisplayMode(.inline)
  }

@ViewBuilder
private var durationValueView: some View {
  if trackRecordingService.isRecording && !trackRecordingService.isPaused {
    TimelineView(.periodic(from: .now, by: 1.0)) { context in
      let liveDuration = trackRecordingService.activeSessionDuration(at: context.date) ?? .seconds(0)
      Text(liveDuration, format: .time(pattern: .hourMinuteSecond))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
  } else {
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
