//
//  LegalDetailView.swift
//  Alcyone Sillage
//

import SwiftUI

struct LegalDetailView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(document.title)
                    .font(.title)
                    .bold()

                Text(document.content)
                    .font(.body)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LegalDetailView(document: LegalDocument(title: "Sample Warning", content: "This is a sample warning text. It should have good contrast and a readable font size."))
    }
}
