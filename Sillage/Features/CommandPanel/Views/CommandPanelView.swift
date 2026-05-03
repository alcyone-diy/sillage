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
        Section {
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
          .listRowSeparator(.hidden)
        }

        // Zone 2: Safety
        Section(header: Text("Safety")) {
          Button(action: {
            // Placeholder
          }) {
            Label {
              Text("Anchor Alarm").marineFont(.body)
            } icon: {
              Image(systemName: "anchor")
                .foregroundStyle(MarineTheme.Colors.textOnActive)
                .padding(MarineTheme.Spacing.small)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius / 2))
            }
            .padding(.vertical, bindableViewModel.isGloveModeEnabled ? MarineTheme.Spacing.medium : 0)
          }

          Button(action: {
            // Placeholder
          }) {
            Label {
              Text("Baro Alarm").marineFont(.body)
            } icon: {
              Image(systemName: "barometer")
                .foregroundStyle(MarineTheme.Colors.textOnActive)
                .padding(MarineTheme.Spacing.small)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius / 2))
            }
            .padding(.vertical, bindableViewModel.isGloveModeEnabled ? MarineTheme.Spacing.medium : 0)
          }
        }

        // Zone 3: System
        Section(header: Text("System")) {
          NavigationLink(value: PanelManagerViewModel.CommandDestination.settings) {
            Label {
              Text("Settings").marineFont(.body)
            } icon: {
              Image(systemName: "gearshape.fill")
                .foregroundStyle(MarineTheme.Colors.textOnActive)
                .padding(MarineTheme.Spacing.small)
                .background(Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius / 2))
            }
            .padding(.vertical, bindableViewModel.isGloveModeEnabled ? MarineTheme.Spacing.medium : 0)
          }
        }
      }
      .listStyle(.insetGrouped)
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
