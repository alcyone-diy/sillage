//
//  TrackRecordingErrorModifier.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-12.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

//
//  TrackRecordingErrorModifier.swift
//  Alcyone Sillage
//

import SwiftUI

@MainActor
struct TrackRecordingErrorModifier: ViewModifier {
  @Environment(TrackRecordingService.self) private var trackRecordingService

  func body(content: Content) -> some View {
    @Bindable var bindableService = trackRecordingService
    
    content
      .alert(
        isPresented: Binding(
          get: { bindableService.recordingError != nil },
          set: { if !$0 { bindableService.recordingError = nil } }
        ),
        error: bindableService.recordingError
      ) { _ in
        Button("OK", role: .cancel) {
          bindableService.recordingError = nil
        }
      } message: { error in
        if let desc = error.errorDescription {
          Text(desc)
        }
      }
  }
}

public extension View {
  @MainActor func handleTrackRecordingErrors() -> some View {
    self.modifier(TrackRecordingErrorModifier())
  }
}
