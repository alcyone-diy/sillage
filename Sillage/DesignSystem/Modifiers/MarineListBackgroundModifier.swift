//
//  MarineListBackgroundModifier.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct MarineListBackgroundModifier: ViewModifier {
  @Environment(\.marineTheme) private var marineTheme

  func body(content: Content) -> some View {
    content
      .scrollContentBackground(.hidden)
      .background(marineTheme.colors.panelBackground)
  }
}

extension View {
  /// Applies the standard marine theme background for lists and panels.
  func marineListBackground() -> some View {
    modifier(MarineListBackgroundModifier())
  }
}
