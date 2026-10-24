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
  @Environment(MessageService.self) private var messageService

  var body: some View {
    @Bindable var bindableViewModel = viewModel
    let hasMessages = !messageService.messages.isEmpty

    Button(action: {
      bindableViewModel.openPanel(.command)
    }) {
      Image(marineIcon: .menu)
        .marineFont(.title2)
        .foregroundColor(.white)
    }
    .buttonStyle(MarineFABStyle(backgroundColor: .blue))
    .marineBadge(isPresent: hasMessages)
  }
}

#Preview("Empty State") {
  CommandButtonView()
    .environment(PanelManagerViewModel())
    .environment(MessageService())
}

#Preview("With Messages") {
  CommandButtonView()
    .environment(PanelManagerViewModel())
    .environment(MessageService.previewWithMessages)
}

#if DEBUG
extension MessageService {
  @MainActor
  static var previewWithMessages: MessageService {
    let service = MessageService()
    service.post(
      AppMessage(
        title: "Weather Alert",
        detail: "Gale force winds forecasted in your area.",
        severity: .warning,
        category: .weather
      )
    )
    return service
  }
}
#endif
