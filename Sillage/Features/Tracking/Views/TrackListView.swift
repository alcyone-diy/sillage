//
//  TrackListView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct TrackListView: View {
  @Environment(\.trackService) private var trackService
  @State private var viewModel = TrackListViewModel()
  
  var body: some View {
    Section(
      header: Text("Saved Tracks")
    ) {
      if viewModel.sessions.isEmpty {
        Text("No saved tracks yet")
          .foregroundStyle(.secondary)
          .marineFont(.body)
          .listRowBackground(Color.clear)
          .marineListCell()
      } else {
        ForEach(viewModel.sessions) { session in
          NavigationLink(value: PanelManagerViewModel.CommandDestination.sessionDetail(sessionId: session.id)) {
            TrackRowView(session: session, subtitle: viewModel.subtitle(for: session))
          }
          .marineListCell()
        }
      }
    }
    .task {
      if let trackService {
        await viewModel.observe(trackService: trackService)
      }
    }
  }
}

@MainActor
struct TrackRowView: View {
  let session: TrackSession
  let subtitle: String?
  
  var body: some View {
    ZStack(alignment: .leading) {
      // Invisible template to enforce uniform height whether it has 1 or 2 lines.
      VStack(alignment: .leading, spacing: 4) {
        Text(" ")
          .marineFont(.body)
        Text(" ")
          .marineFont(.caption)
      }
      .hidden()
      
      VStack(alignment: .leading, spacing: 4) {
        if let name = session.name {
          Text(name)
            .marineFont(.body)
        } else {
          Text(session.startTime.formatted(date: .complete, time: .shortened))
            .marineFont(.body)
        }
        
        if let subtitle = subtitle {
          Text(verbatim: subtitle)
            .foregroundStyle(.secondary)
            .marineFont(.caption)
        }
      }
    }
  }
}
