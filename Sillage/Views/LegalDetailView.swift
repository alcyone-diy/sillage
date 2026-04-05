//
//  LegalDetailView.swift
//  Alcyone Sillage
//

import SwiftUI

struct LegalDetailView: View {
    @State private var viewModel: LegalDetailViewModel

    init(document: LegalDocument) {
        _viewModel = State(initialValue: LegalDetailViewModel(document: document))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                VStack {
                    if viewModel.showSpinner {
                        ProgressView("Loading...")
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Color.clear // Empty state during the 150ms anti-flicker window
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let content):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(viewModel.document.title)
                            .font(.title)
                            .bold()

                        Text(content)
                            .font(.body)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .error(let errorMessage):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
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
        .navigationTitle(viewModel.document.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadContent()
        }
    }
}

#Preview {
    NavigationStack {
        LegalDetailView(document: LegalDocument(title: "Sample Warning", content: "This is a sample warning text. It should have good contrast and a readable font size."))
    }
}
