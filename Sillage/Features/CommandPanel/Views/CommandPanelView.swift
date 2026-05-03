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
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    @Bindable var bindableViewModel = viewModel

    NavigationStack(path: $bindableViewModel.commandPath) {
      List {
        // Zone 1: Quick Actions
        Section(header: Text("Quick Actions")) {
          HStack(spacing: MarineTheme.Spacing.medium) {
            MarineToggleButton(
              title: "Glove Mode",
              systemImage: "hand.raised.fill",
              isOn: $bindableViewModel.isGloveModeEnabled
            )

            MarineToggleButton(
              title: "Track",
              systemImage: "record.circle",
              isOn: .constant(false)
            )
          }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }

        // Zone 2: Safety
        Section(header: Text("Safety")) {
          Button(action: {
            // Placeholder
          }) {
            HStack {
              Image(systemName: "anchor")
                .foregroundColor(.secondary)
              Text("Anchor Alarm")
                .marineFont(.body)
                .foregroundColor(.primary)
              Spacer()
            }
          }

          Button(action: {
            // Placeholder
          }) {
            HStack {
              Image(systemName: "barometer")
                .foregroundColor(.secondary)
              Text("Baro Alarm")
                .marineFont(.body)
                .foregroundColor(.primary)
              Spacer()
            }
          }
        }

        // Zone 3: System
        Section(header: Text("System")) {
          Button(action: {
            bindableViewModel.commandPath.append(PanelManagerViewModel.CommandDestination.settings)
          }) {
            HStack {
              Image(systemName: "gearshape.fill")
                .foregroundColor(.secondary)
              Text("Settings")
                .marineFont(.body)
                .foregroundColor(.primary)
              Spacer()
            }
          }
        }
      }
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
