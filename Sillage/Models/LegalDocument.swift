//
//  LegalDocument.swift
//  Sillage
//

import Foundation

struct LegalDocument: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}
