//
//  CommandButtonView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//

import SwiftUI

struct CommandButtonView: View {
  @Environment(CommandPanelViewModel.self) private var commandPanelViewModel

  var body: some View {
    Button(action: {
      commandPanelViewModel.isPanelOpen.toggle()
    }) {
      Image(systemName: "line.3.horizontal")
        .font(.title2.weight(.bold))
        .foregroundColor(.white)
    }
    .buttonStyle(MarineFABStyle(backgroundColor: .blue))
  }
}

#Preview {
  CommandButtonView()
    .environment(CommandPanelViewModel())
    .environment(\.marineTheme, .standard)
}
