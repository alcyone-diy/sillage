//
//  MarineCellBackgroundView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import UIKit

/// A view that perfectly matches the native UIKit grouped cell background.
/// By using a UIView, we guarantee that it receives the correct `UITraitCollection`
/// from the view hierarchy (e.g. `userInterfaceLevel = .elevated` in modal sheets),
/// which fixes the SwiftUI bug where `Color(uiColor:)` sometimes fails to elevate.
struct MarineCellBackgroundView: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.backgroundColor = .secondarySystemGroupedBackground
    return view
  }
  
  func updateUIView(_ uiView: UIView, context: Context) {
    uiView.backgroundColor = .secondarySystemGroupedBackground
  }
}
