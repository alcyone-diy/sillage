//
//  SettingsView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(AppViewModel.self) private var appViewModel
  @Environment(\.marineTheme) private var marineTheme
  @State private var viewModel = SettingsViewModel()

  var body: some View {
    Form {
      Section(header: Text("General").marineFont(.headline)) {
        @Bindable var bindableAppViewModel = appViewModel
          Toggle(isOn: $bindableAppViewModel.isGloveModeEnabled) {
            Label("Glove Mode", systemImage: "hand.raised.fill")
              .marineFont(.body)
          }

          NavigationLink(destination: MapPreferencesView()) {
            Label("Map Preferences", systemImage: "map")
              .marineFont(.body)
          }
        }

      Section(header: Text("Safety & Legal").marineFont(.headline)) {
        NavigationLink(destination: LegalListView(documents: viewModel.legalDocuments)) {
          Label("Legal & Licenses", systemImage: "doc.text")
            .marineFont(.body)
        }
      }

      Section(header: Text("About").marineFont(.headline)) {
        HStack {
          Label("Version", systemImage: "info.circle")
            .marineFont(.body)
          Spacer()
          Text("1.0.0")
            .marineFont(.body)
            .foregroundColor(.secondary)
        }
      }
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  SettingsView()
    .environment(AppViewModel())
    .environment(\.marineTheme, .standard)
}
