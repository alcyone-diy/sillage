//
//  NativeTextView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import UIKit

struct NativeTextView: UIViewRepresentable {
  let text: String

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.isEditable = false
    textView.isSelectable = true
    textView.backgroundColor = .clear
    textView.font = UIFont.preferredFont(forTextStyle: .body)
    // Ensure the text starts at the top
    textView.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
    return textView
  }

  func updateUIView(_ uiView: UITextView, context: Context) {
    uiView.text = text
  }
}
