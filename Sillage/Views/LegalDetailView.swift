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
                Color.clear
            case .loaded(let content):
                NativeTextView(text: content)
                    .ignoresSafeArea(edges: .bottom)
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
