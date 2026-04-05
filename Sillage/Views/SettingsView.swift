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
  @State private var viewModel = SettingsViewModel()

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text("General").marineFont(.headline)) {
          @Bindable var bindableAppViewModel = appViewModel
          Toggle(isOn: $bindableAppViewModel.isGloveModeEnabled) {
            Label("Glove Mode", systemImage: "hand.raised.fill")
              .marineFont(.body)
          }
          .marineListCell()

          NavigationLink(destination: MapPreferencesView()) {
            Label("Map Preferences", systemImage: "map")
              .marineFont(.body)
              .marineListCell()
          }
        }

        Section(header: Text("Accounts").marineFont(.headline)) {
          NavigationLink(destination: GeoGarageLoginView()) {
            Label("GeoGarage Account", systemImage: "person.crop.circle")
              .marineFont(.body)
              .marineListCell()
          }
        }

        Section(header: Text("Safety & Legal").marineFont(.headline)) {
          NavigationLink(destination: LegalListView(documents: viewModel.legalDocuments)) {
            Label("Legal & Licenses", systemImage: "doc.text")
              .marineFont(.body)
              .marineListCell()
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
          .marineListCell()
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

#Preview {
  SettingsView()
    .environment(AppViewModel())
    .environment(\.marineTheme, .standard)
}
