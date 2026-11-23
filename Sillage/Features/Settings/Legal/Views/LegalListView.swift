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
  @Environment(\.marineTheme) private var marineTheme
  @State private var viewModel = LegalListViewModel()

  var body: some View {
    List {
      Section {
        documentRow(for: viewModel.navigationWarningDocument)
        documentRow(for: viewModel.sillageLicenseDocument)
      } header: {
        Text(AppConstants.appName)
          .marineSectionHeader()
      }
      Section {
        ForEach(viewModel.thirdPartyLicenseDocuments) { document in
          documentRow(for: document)
        }
      } header: {
        Text("Third-Party Licenses")
          .marineSectionHeader()
      }
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .marineListBackground()
    .navigationTitle("Legal & Licenses")
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private func documentRow(for document: LegalDocument) -> some View {
    NavigationLink(value: PanelManagerViewModel.CommandDestination.legalDetail(document.id)) {
      Text(document.title)
        .marineFont(.body)
        .foregroundColor(.primary)
    }
    .marineListCell()
  }
}
