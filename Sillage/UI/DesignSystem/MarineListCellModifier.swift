//
//  MarineListCellModifier.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct MarineListCellModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .contentShape(Rectangle())
  }
}

extension View {
  func marineListCell() -> some View {
    self.modifier(MarineListCellModifier())
  }
}
