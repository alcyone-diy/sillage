//
//  TrackRecordingToggleView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-12.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct TrackRecordingToggleView: View {
  @Environment(TrackRecordingService.self) private var trackRecordingService
  @Environment(AppViewModel.self) private var appViewModel

  var body: some View {
    @Bindable var bindableTrackRecordingService = trackRecordingService

    MarineToggleButton(
      title: "Track",
      systemImage: "record.circle",
      isOn: Binding(
        get: { trackRecordingService.isRecording },
        set: { _ in trackRecordingService.toggleRecording() }
      )
    )
    .disabled(!appViewModel.isDatabaseReady)
    .disabled(trackRecordingService.isSaving)
    .alert(
      "Recording Error",
      isPresented: Binding(
        get: { trackRecordingService.recordingError != nil },
        set: { if !$0 { trackRecordingService.recordingError = nil } }
      ),
      presenting: trackRecordingService.recordingError
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { error in
      Text(error.localizedDescription)
    }
  }
}
