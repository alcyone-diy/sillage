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
      Section {
        Toggle(isOn: Bindable(appViewModel).isGloveModeEnabled) {
          Label("Glove Mode", systemImage: "hand.raised.fill")
            .marineFont(.body)
        }
        .marineListCell()
        
        NavigationLink(value: PanelManagerViewModel.CommandDestination.chartPreferences) {
          Label("Chart Preferences", systemImage: "map")
            .marineFont(.body)
        }
        .marineListCell()
      } header: {
        Text("General").marineSectionHeader()
      }
      
      Section {
        NavigationLink(destination: COGPreferencesView()) {
          Label("Predictor Vector", systemImage: "location.north.line.fill")
            .marineFont(.body)
        }
        .marineListCell()
      } header: {
        Text("Navigation").marineSectionHeader()
      }
      
      Section {
        NavigationLink(value: PanelManagerViewModel.CommandDestination.checklistCategories) {
          Label("Checklist Categories", systemImage: "tag")
            .marineFont(.body)
        }
        .marineListCell()
      } header: {
        Text("Safety").marineSectionHeader()
      }
      
      Section {
        NavigationLink(
          destination: LegalListView(
            navigationWarningDocument: viewModel.navigationWarningDocument,
            sillageLicenseDocument: viewModel.sillageLicenseDocument,
            thirdPartyLicenseDocuments: viewModel.thirdPartyLicenseDocuments
          )
        ) {
          Label("Legal & Licenses", systemImage: "doc.text")
            .marineFont(.body)
        }
        .marineListCell()
      } header: {
        Text("Legal").marineSectionHeader()
      }
      
      Section {
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
        
        Link(destination: AppConstants.appURL) {
          HStack {
            Label("Website", systemImage: "globe")
              .marineFont(.body)
            Spacer()
            Image(systemName: "arrow.up.right")
              .marineFont(.body)
              .foregroundStyle(.secondary)
          }
        }
        .tint(.primary)
        .marineListCell()
      } header: {
        Text("About").marineSectionHeader()
      }
      
#if DEBUG
      Section {
        NavigationLink(destination: DebugView()) {
          Label("Debug Menu", systemImage: "ladybug")
            .marineFont(.body)
        }
        .marineListCell()
      } header: {
        Text("Debug").marineSectionHeader()
      }
#endif
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .marineListBackground()
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  SettingsView()
    .environment(AppViewModel(preferencesService: PreferencesService()))
    .environment(\.marineTheme, .standard)
}
