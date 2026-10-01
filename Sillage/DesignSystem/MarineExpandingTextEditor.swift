//
//  MarineExpandingTextEditor.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-30.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Multi-line text editor that increases automatically using
/// the enter key.
struct MarineExpandingTextEditor: View {
  @Environment(\.marineTheme) private var marineTheme

  let placeholder: LocalizedStringKey
  @Binding var text: String
  var minHeight: CGFloat = 88
  
  var body: some View {
    ZStack(alignment: .topLeading) {
      // Needed to have the right height automatically.
      Text(text.isEmpty ? " " : text)
        .marineFont(.body)
        .opacity(0)
        .accessibilityHidden(true)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
      
      TextEditor(text: $text)
        .scrollContentBackground(.hidden)
        .marineFont(.body)
        .foregroundStyle(marineTheme.colors.textPrimary)
        .padding(.horizontal, -5)
      
      // Manual placeholder.
      if text.isEmpty {
        Text(placeholder)
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .padding(.top, 8)
          .allowsHitTesting(false)
      }
    }
  }
}
