//
//  LegalListView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct LegalListView: View {
  let navigationWarningDocument: LegalDocument
  let sillageLicenseDocument: LegalDocument
  let thirdPartyLicenseDocuments: [LegalDocument]
  
  // 1. Injection du thème pour le Glove Mode
  @Environment(\.marineTheme) private var marineTheme
  
  var body: some View {
    List {
      Section {
        documentRow(for: navigationWarningDocument)
        documentRow(for: sillageLicenseDocument)
      } header: {
        Text("Alcyone Sillage")
      }
      Section {
        ForEach(thirdPartyLicenseDocuments) { document in
          documentRow(for: document)
        }
      } header: {
        Text("Third-Party Licenses")
      }
      .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
      .navigationTitle("Legal & Licenses")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
  
  @ViewBuilder
  private func documentRow(for document: LegalDocument) -> some View {
    NavigationLink(destination: LegalDetailView(document: document)) {
      Text(document.title)
        .marineFont(.body)
        .foregroundColor(.primary)
    }
  }
}
