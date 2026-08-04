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
        Toggle(isOn: Bindable(appViewModel).isGloveModeEnabled) {
          Label("Glove Mode", systemImage: "hand.raised.fill")
            .marineFont(.body)
        }
        .marineListCell()
        
        NavigationLink(destination: ChartPreferencesView()) {
          Label("Chart Preferences", systemImage: "map")
            .marineFont(.body)
        }
        .marineListCell()
      }
      
      Section(header: Text("Storage & Charts")) {
        NavigationLink(destination: OfflineRegionsManagerView()) {
          HStack {
            Label {
              VStack(alignment: .leading, spacing: 4) {
                Text("Offline Charts")
                if let progress = environment.offlineMapManager.globalDownloadProgress, environment.offlineMapManager.totalPendingDownloads > 0 {
                  ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(marineTheme.colors.accent)
                }
              }
            } icon: {
              Image(systemName: "square.and.arrow.down.on.square")
            }
            .marineFont(.body)
            Spacer()
          }
        }
        .animation(.default, value: environment.offlineMapManager.totalPendingDownloads > 0)
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
      }
      
#if DEBUG
      Section(header: Text("Debug")) {
        NavigationLink(destination: DebugView()) {
          Label("Debug Menu", systemImage: "ladybug")
            .marineFont(.body)
        }
        .marineListCell()
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
    .environment(AppViewModel(preferencesService: PreferencesService(), panelManagerViewModel: PanelManagerViewModel()))
    .environment(\.marineTheme, .standard)
}
