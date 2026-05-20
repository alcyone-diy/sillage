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
            TrackRowView(session: session)
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
  
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let name = session.name {
        Text(name)
          .marineFont(.body)
      } else {
        Text(session.startTime.formatted(date: .complete, time: .shortened))
          .marineFont(.body)
      }
      
      if let subtitle = subtitle(for: session) {
        Text(verbatim: subtitle)
          .foregroundStyle(.secondary)
          .marineFont(.caption)
      }
    }
  }
  
  private func subtitle(for session: TrackSession) -> String? {
    var components: [String] = []
    if let distance = session.totalDistance {
      let distStr = distance.converted(to: .nauticalMiles).formatted(
        .measurement(
          width: .abbreviated,
          usage: .asProvided,
          numberFormatStyle: .number.precision(.fractionLength(2))
        )
      )
      components.append(distStr)
    }
    if let duration = session.duration {
      components.append(duration.marineFormatted)
    }
    if session.name != nil {
      components.append(session.startTime.formatted(date: .abbreviated, time: .shortened))
    }
    if components.isEmpty { return nil }
    return components.joined(separator: " • ")
  }
}
