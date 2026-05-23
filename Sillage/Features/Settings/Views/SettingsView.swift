//
//  SettingsView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(AppViewModel.self) private var appViewModel
  @Environment(AppEnvironment.self) private var environment
  @Environment(\.marineTheme) private var marineTheme
  @State private var viewModel = SettingsViewModel()

  var body: some View {
    Form {
      Section(header: Text("General")) {
        @Bindable var bindableAppViewModel = appViewModel
          Toggle(isOn: $bindableAppViewModel.isGloveModeEnabled) {
            Label("Glove Mode", systemImage: "hand.raised.fill")
              .marineFont(.body)
          }
          .marineListCell()

          NavigationLink(destination: MapPreferencesView()) {
            Label("Map Preferences", systemImage: "map")
              .marineFont(.body)
          }
          .marineListCell()
        }

      Section(header: Text("Navigation")) {
        NavigationLink(destination: COGPreferencesView()) {
          Label("Predictor Vector", systemImage: "location.north.line.fill")
            .marineFont(.body)
        }
        .marineListCell()
      }

      Section(header: Text("Safety & Legal")) {
        NavigationLink(destination: LegalListView(documents: viewModel.legalDocuments)) {
          Label("Legal & Licenses", systemImage: "doc.text")
            .marineFont(.body)
        }
        .marineListCell()
      }

      Section(header: Text("About")) {
        NavigationLink(destination: VersionInfoView()) {
          HStack {
            Label("Version", systemImage: "info.circle")
              .marineFont(.body)
            Spacer()
            Text(environment.metadata.version ?? "Unknown")
              .marineFont(.body)
              .foregroundStyle(.secondary)
          }
        }
        .marineListCell()
      }
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  SettingsView()
    .environment(AppViewModel(preferencesService: PreferencesService()))
    .environment(\.marineTheme, .standard)
}
