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
        Button(action: {
          bindableViewModel.commandPath.append(PanelManagerViewModel.CommandDestination.settings)
        }) {
          HStack {
            Image(systemName: "gearshape.fill")
              .foregroundColor(.secondary)
            Text("Settings")
              .marineFont(.body)
              .foregroundColor(.primary)
          }
        }
        .marineListCell()
      }
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
