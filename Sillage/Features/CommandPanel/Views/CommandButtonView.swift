//
//  CommandButtonView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct CommandButtonView: View {
  @Environment(PanelManagerViewModel.self) private var viewModel

  var body: some View {
    @Bindable var bindableViewModel = viewModel
    Button(action: {
      bindableViewModel.openPanel(.command)
    }) {
      Image(marineIcon: .menu)
        .marineFont(.title2)
        .foregroundColor(.white)
    }
    .buttonStyle(MarineFABStyle(backgroundColor: .blue))
  }
}

#Preview {
  CommandButtonView()
    .environment(PanelManagerViewModel())
}
