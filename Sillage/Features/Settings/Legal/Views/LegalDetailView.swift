//
//  LegalDetailView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct LegalDetailView: View {
  @State private var viewModel: LegalDetailViewModel

  init(documentID: LegalDocumentID) {
    self.init(document: LegalDocument.document(for: documentID))
  }

  init(document: LegalDocument) {
    _viewModel = State(wrappedValue: LegalDetailViewModel(document: document))
  }

  var body: some View {
    Group {
      switch viewModel.state {
      case .loading:
        Color.clear
      case .loaded(let content):
        NativeTextView(text: content)
          .ignoresSafeArea(edges: .bottom)
      case .error(let errorMessage):
        VStack(spacing: 16) {
          Image(marineIcon: .warning)
            .font(.largeTitle)
            .foregroundColor(.red)
          Text("Error loading document")
            .font(.headline)
          Text(errorMessage)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
      }
    }
    .navigationTitle(Text(viewModel.document.title))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadContent()
    }
  }
}

#Preview {
  NavigationStack {
    LegalDetailView(documentID: .navigationWarning)
  }
}
