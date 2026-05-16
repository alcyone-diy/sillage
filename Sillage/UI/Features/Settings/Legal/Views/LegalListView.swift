//
//  LegalListView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct LegalListView: View {
  let documents: [LegalDocument]
  
  // 1. Injection du thème pour le Glove Mode
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    List(documents) { document in
      NavigationLink(destination: LegalDetailView(document: document)) {
        // 2. Nettoyage du frame et application de la typo marine
        Text(document.title)
          .marineFont(.body)
          .foregroundColor(.primary)
      }
    }
    // 3. Pilotage global de la hauteur de ligne
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle("Legal & Licenses")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    LegalListView(documents: [
      LegalDocument(title: "Sample Warning", content: "This is a sample warning."),
      LegalDocument(title: "Sample License", content: "This is a sample license.")
    ])
    .environment(\.marineTheme, .standard)
  }
}
