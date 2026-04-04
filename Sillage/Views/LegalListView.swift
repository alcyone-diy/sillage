//
//  LegalListView.swift
//  Alcyone Sillage
//

import SwiftUI

struct LegalListView: View {
    let documents: [LegalDocument]

    var body: some View {
        List(documents) { document in
            NavigationLink(destination: LegalDetailView(document: document)) {
                Text(document.title)
                    .frame(minHeight: 60, alignment: .leading)
                    .contentShape(Rectangle())
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
