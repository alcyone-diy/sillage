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
  var body: some View {
    List {
      TrackControlView()
      TrackListView()
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(MarineTheme.Colors.panelBackground)
    .handleTrackRecordingErrors()
    .navigationTitle("Track Manager")
    .navigationBarTitleDisplayMode(.inline)
  }
}
