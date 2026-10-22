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
  @Environment(AppEnvironment.self) private var appEnvironment
  @Environment(TrackRecordingService.self) private var trackRecordingService
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManager
  @Environment(\.marineTheme) private var marineTheme
  
  @State private var viewModel = TrackListViewModel()
  
  @State private var sessionToDelete: TrackSession?
  
  var body: some View {
    Section {
      if viewModel.sessions.isEmpty {
        Text("No saved tracks yet")
          .foregroundStyle(.secondary)
          .marineFont(.body)
          .listRowBackground(Color.clear)
          .marineListCell()
      } else {
        ForEach(viewModel.sessions) { session in
          let isVisible = chartViewModel.displayedTrackSessionID == session.id
          NavigationLink(value: PanelManagerViewModel.CommandDestination.sessionDetail(sessionID: session.id, session: session)) {
            TrackRowView(
              session: session,
              subtitle: viewModel.subtitle(for: session),
              isSelected: isVisible
            )
          }
          .marineListCell()
          .accessibilityLabel(accessibilityLabel(for: session, isVisible: isVisible))
          .swipeActions(edge: .leading, allowsFullSwipe: !isVisible) {
            if isVisible {
              Button {
                chartViewModel.clearSavedTrack()
              } label: {
                Label("Hide from Chart", systemImage: MarineIcon.visibilityOff.rawValue)
              }
              .tint(marineTheme.colors.cancelAction)
            } else {
              Button {
                Task {
                  do {
                    try await chartViewModel.loadAndDisplaySavedTrack(sessionID: session.id)
                    panelManager.closePanel()
                  } catch {
                    Logger.chart.error("Failed to display track \(session.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    viewModel.activeError = .loadFailed
                  }
                }
              } label: {
                Label("Show on Chart", systemImage: MarineIcon.visibilityOn.rawValue)
              }
              .tint(.blue)
            }
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !trackRecordingService.isSessionActive(session.id) {
              Button(role: .destructive) {
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
    } header: {
      Text("Saved Tracks").marineSectionHeader()
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
        viewModel.deleteSession(
          session,
          trackService: appEnvironment.trackService,
          trackRecordingService: trackRecordingService
        )
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
      await viewModel.observe(trackService: appEnvironment.trackService)
    }
  }

  private func accessibilityLabel(for session: TrackSession, isVisible: Bool) -> Text {
    let title = session.name ?? session.startTime.formatted(date: .complete, time: .shortened)
    let subtitle = viewModel.subtitle(for: session)

    let components: [String?] = [
      title,
      subtitle,
      isVisible ? String(localized: "Visible on chart") : nil
    ]
    let labelString = components.compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: ", ")
    return Text(labelString)
  }
}

@MainActor
struct TrackRowView: View {
  let session: TrackSession
  let subtitle: String?
  let isSelected: Bool
  @Environment(\.marineTheme) private var marineTheme
  
  var body: some View {
    HStack {
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
      
      Spacer()
      
      if isSelected {
        Image(marineIcon: .visibilityOn)
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.primary)
          .accessibilityHidden(true)
      }
    }
  }
}
