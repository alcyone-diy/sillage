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

  var body: some View {
    List(documents) { document in
      NavigationLink(destination: LegalDetailView(document: document)) {
        Text(document.title)
          .frame(maxWidth: .infinity, alignment: .leading)
          .marineListCell()
      }
    }
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
  }
}
