//
//  CommandPanelView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//

import SwiftUI

struct CommandPanelView: View {
  @Environment(CommandPanelViewModel.self) private var commandPanelViewModel
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    NavigationStack {
      List {
        Section {
          NavigationLink(destination: SettingsView()) {
            Label("Settings", systemImage: "gearshape.fill")
              .marineFont(.body)
          }
          .marineListCell()
        }
      }
      .navigationTitle("Commands")
      .navigationBarTitleDisplayMode(.inline)
      .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: {
            commandPanelViewModel.isPanelOpen = false
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
    .environment(CommandPanelViewModel())
    .environment(\.marineTheme, .standard)
}
