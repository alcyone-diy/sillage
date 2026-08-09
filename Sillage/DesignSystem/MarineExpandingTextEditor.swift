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

/// Multi lne text editor that increases automaticaly using
/// the enter key.
struct MarineExpandingTextEditor: View {
  let placeholder: LocalizedStringKey
  @Binding var text: String
  var minHeight: CGFloat = 88
  
  var body: some View {
    ZStack(alignment: .topLeading) {
      // Needed to have the right height automatically.
      Text(text.isEmpty ? " " : text)
        .marineFont(.body)
        .foregroundColor(.clear)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
      
      TextEditor(text: $text)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, -5)
      
      // Manual placeholder.
      if text.isEmpty {
        Text(placeholder)
          .marineFont(.body)
          .foregroundStyle(.secondary)
          .padding(.top, 8)
          .allowsHitTesting(false)
      }
    }
  }
}
