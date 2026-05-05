//
//  CommandPanelView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct CommandPanelView: View {
  @Environment(PanelManagerViewModel.self) private var viewModel
  @Environment(AppViewModel.self) private var appViewModel
  @Environment(TrackRecordingService.self) private var trackRecordingService
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    @Bindable var bindableViewModel = viewModel
    @Bindable var bindableAppViewModel = appViewModel
    @Bindable var bindableTrackRecordingService = trackRecordingService

    NavigationStack(path: $bindableViewModel.commandPath) {
      List {
        // Zone 1: Quick Actions
        Section(header: Text("Quick Actions")) {
          HStack(spacing: MarineTheme.Spacing.medium) {
            MarineToggleButton(
              title: "Glove Mode",
              systemImage: "hand.raised.fill",
              isOn: $bindableAppViewModel.isGloveModeEnabled
            )

            MarineToggleButton(
              title: "Track",
              systemImage: "record.circle",
              isOn: $bindableTrackRecordingService.isRecording
            )
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
                      Image(systemName: "location.viewfinder").foregroundStyle(.blue)
                  }
                  .marineFont(.body)
                  .marineListCell()
              }.tint(.primary)
          Button(action: {
              }) {
                  Label {
                      Text("Baro Alarm").foregroundStyle(.primary)
                  } icon: {
                      Image(systemName: "barometer").foregroundStyle(.blue)
                  }
                  .marineFont(.body)
                  .marineListCell()
              }.tint(.primary)
        }

        // Zone 3: System
        Section(header: Text("System")) {
          NavigationLink(value: PanelManagerViewModel.CommandDestination.settings) {
            Label("Settings", systemImage: "gearshape.fill")
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
        }
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: {
            bindableViewModel.closePanel()
          }) {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.tertiary)
              .font(.title2)
          }
        }
      }
    }
  }
}

#Preview {
  CommandPanelView()
    .environment(PanelManagerViewModel())
    .environment(\.marineTheme, .standard)
}
