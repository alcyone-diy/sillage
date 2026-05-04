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
      Section(header: Text(String(localized: "General"))) {
        @Bindable var bindableAppViewModel = appViewModel
          Toggle(isOn: $bindableAppViewModel.isGloveModeEnabled) {
            Label(String(localized: "Glove Mode"), systemImage: "hand.raised.fill")
              .marineFont(.body)
          }
          .marineListCell()

          NavigationLink(destination: MapPreferencesView()) {
            Label(String(localized: "Map Preferences"), systemImage: "map")
              .marineFont(.body)
          }
          .marineListCell()
        }

      Section(header: Text(String(localized: "Navigation"))) {
        NavigationLink(destination: COGPreferencesView()) {
          Label(String(localized: "Predictor Vector"), systemImage: "location.north.line.fill")
            .marineFont(.body)
        }
        .marineListCell()
      }

      Section(header: Text(String(localized: "Safety & Legal"))) {
        NavigationLink(destination: LegalListView(documents: viewModel.legalDocuments)) {
          Label(String(localized: "Legal & Licenses"), systemImage: "doc.text")
            .marineFont(.body)
        }
        .marineListCell()
      }

      Section(header: Text(String(localized: "About"))) {
        HStack {
          Label(String(localized: "Version"), systemImage: "info.circle")
            .marineFont(.body)
          Spacer()
          Text("1.0.0")
            .marineFont(.body)
            .foregroundStyle(.secondary)
        }
        .marineListCell()
      }
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle(String(localized: "Settings"))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  SettingsView()
    .environment(AppViewModel())
    .environment(\.marineTheme, .standard)
}
