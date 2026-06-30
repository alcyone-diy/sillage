//
//  CommandPanelView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import OSLog
import CoreLocation

@MainActor
struct CommandPanelView: View {
  @Environment(PanelManagerViewModel.self) private var viewModel
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(AppViewModel.self) private var appViewModel
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.trackService) private var trackService
  @Environment(\.waypointService) private var waypointService
  @Environment(TrackRecordingService.self) private var trackRecordingService
  
  @Environment(ActiveTrackViewModel.self) private var activeTrackViewModel
  
  var body: some View {
    @Bindable var bindableViewModel = viewModel
    @Bindable var bindableAppViewModel = appViewModel
    @Bindable var bindableActiveTrackViewModel = activeTrackViewModel
    
    NavigationStack(path: $bindableViewModel.commandPath) {
      List {
        // Zone 1: Quick Actions
        Section(header: Text("Quick Actions")) {
          HStack(spacing: MarineTheme.Spacing.medium) {
            MarineToggleButton(
              title: "Glove Mode",
              icon: .gloveMode,
              isOn: $bindableAppViewModel.isGloveModeEnabled
            )
            
            MarineToggleButton(
              title: "Track",
              icon: .record,
              isOn: Binding(
                get: { activeTrackViewModel.isRecording },
                set: { _ in activeTrackViewModel.toggleRecording() }
              )
            )
            .disabled(activeTrackViewModel.isSaving)
          }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }
        
        // Zone 2: Safety
        Section(header: Text("Safety")) {
          Button(action: {
          }) {
            Label {
              Text("Anchor Alarm").foregroundStyle(.primary)
            } icon: {
              Image(marineIcon: .location).foregroundStyle(.blue)
            }
            .marineFont(.body)
            .marineListCell()
          }.tint(.primary)
          Button(action: {
          }) {
            Label {
              Text("Baro Alarm").foregroundStyle(.primary)
            } icon: {
              Image(marineIcon: .instruments).foregroundStyle(.blue)
            }
            .marineFont(.body)
            .marineListCell()
          }.tint(.primary)
        }
        
        Section(header: Text("Navigation")) {
          NavigationLink(value: PanelManagerViewModel.CommandDestination.tracks) {
            Label {
              Text("Tracks").foregroundStyle(.primary)
            } icon: {
              Image(marineIcon: .track).foregroundStyle(.blue)
            }
            .marineFont(.body)
          }
          .marineListCell()
          
          NavigationLink(value: PanelManagerViewModel.CommandDestination.waypoints) {
            Label {
              Text("Waypoints").foregroundStyle(.primary)
            } icon: {
              Image(marineIcon: .waypoint).foregroundStyle(.blue)
            }
            .marineFont(.body)
          }
          .marineListCell()
        }
        
        // Zone 3: System
        Section(header: Text("System")) {
          NavigationLink(value: PanelManagerViewModel.CommandDestination.settings) {
            Label("Settings", systemImage: MarineIcon.settings.rawValue)
              .marineFont(.body)
          }
          .marineListCell()
        }
      }
      .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(MarineTheme.Colors.panelBackground)
      .navigationTitle("Command Panel")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: PanelManagerViewModel.CommandDestination.self) { destination in
        switch destination {
        case .settings:
          SettingsView()
        case .tracks:
          TracksManagerView()
        case .waypoints:
          if let waypointService {
            let model = WaypointListViewModel(waypointService: waypointService)
            WaypointListView(viewModel: model)
          }
        case .sessionDetail(let sessionID):
          if let trackService {
            let model = TrackDetailViewModel(
              sessionID: sessionID,
              trackService: trackService,
              trackRecordingService: trackRecordingService
            )
            TrackDetailView(viewModel: model) { id in
              try await chartViewModel.loadAndDisplaySavedTrack(
                sessionID: id,
                trackService: trackService,
                edgePadding: MarineTheme.Spacing.large
              )
              viewModel.closePanel()
            }
          }
        case .waypointDetail(let id):
          WaypointDetailContainer(waypointID: id)
        }
      }
      .handleTrackRecordingErrors()
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
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: {
            bindableViewModel.closePanel()
          }) {
            Image(marineIcon: .cancelAction)
              .foregroundStyle(.tertiary)
              .font(.title2)
          }
        }
      }
    }
  }
}
