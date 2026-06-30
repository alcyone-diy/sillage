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
import OSLog

@MainActor
struct TrackListView: View {
  @Environment(\.trackService) private var trackService
  @Environment(TrackRecordingService.self) private var trackRecordingService
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManager
  
  @State private var viewModel = TrackListViewModel()
  
  @State private var sessionToDelete: TrackSession?
  
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
          NavigationLink(value: PanelManagerViewModel.CommandDestination.sessionDetail(sessionID: session.id)) {
            TrackRowView(session: session, subtitle: viewModel.subtitle(for: session))
          }
          .swipeActions(edge: .leading) {
            let isVisible = chartViewModel.displayedTrackSessionID == session.id
            if isVisible {
              Button {
                chartViewModel.clearSavedTrack()
              } label: {
                Label("Hide", systemImage: MarineIcon.track.rawValue)
              }
              .tint(MarineTheme.Colors.cancelAction)
            } else {
              Button {
                Task {
                  if let trackService {
                    do {
                      try await chartViewModel.loadAndDisplaySavedTrack(
                        sessionID: session.id,
                        trackService: trackService,
                        edgePadding: MarineTheme.Spacing.large
                      )
                      panelManager.closePanel()
                    } catch {
                      Logger.chart.error("Failed to display track \(session.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                      viewModel.activeError = .loadFailed
                    }
                  }
                }
              } label: {
                Label("Show", systemImage: MarineIcon.track.rawValue)
              }
              .tint(.blue)
            }
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !trackRecordingService.isSessionActive(session.id) {
              Button {
                sessionToDelete = session
              } label: {
                Label("Delete", systemImage: MarineIcon.delete.rawValue)
              }
              .tint(.red)
            }
          }
          .marineListCell()
        }
      }
    }
    .alert(
      "Delete Track?",
      isPresented: Binding(
        get: { sessionToDelete != nil },
        set: { if !$0 { sessionToDelete = nil } }
      ),
      presenting: sessionToDelete
    ) { session in
      Button("Delete", role: .destructive) {
        if let trackService {
          viewModel.deleteSession(
            session,
            trackService: trackService,
            trackRecordingService: trackRecordingService
          )
        }
      }
      Button("Cancel", role: .cancel) {
        sessionToDelete = nil
      }
    } message: { _ in
      Text("Are you sure you want to delete this track? This action cannot be undone.")
    }
    .alert(
      isPresented: Binding(
        get: { viewModel.activeError != nil },
        set: { if !$0 { viewModel.activeError = nil } }
      ),
      error: viewModel.activeError
    ) { _ in
      Button("OK", role: .cancel) { }
    } message: { error in
      Text(error.localizedDescription)
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
