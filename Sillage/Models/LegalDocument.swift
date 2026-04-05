//
//  LegalDocument.swift
//  Alcyone Sillage
//

import Foundation

struct LegalDocument: Identifiable {
    let id = UUID()
    let title: String
    let content: String?
    let filename: String?
    let fileExtension: String?

    init(title: String, content: String? = nil, filename: String? = nil, fileExtension: String? = nil) {
        self.title = title
        self.content = content
        self.filename = filename
        self.fileExtension = fileExtension
    }
}
