//
//  LegalDetailViewModel.swift
//  Alcyone Sillage
//

import Foundation
import Observation

@MainActor
@Observable
class LegalDetailViewModel {
    enum ViewState {
        case loading
        case loaded(String)
        case error(String)
    }

    var state: ViewState = .loading

    let document: LegalDocument

    init(document: LegalDocument) {
        self.document = document
    }

    func loadContent() async {
        if let content = document.content {
            self.state = .loaded(content)
            return
        }

        guard let filename = document.filename, let ext = document.fileExtension else {
            self.state = .error("Invalid document reference.")
            return
        }

        self.state = .loading

        do {
            let content = try await Self.readFile(filename: filename, fileExtension: ext)
            self.state = .loaded(content)
        } catch {
            self.state = .error("Failed to load document: \(error.localizedDescription)")
        }
    }

    nonisolated private static func readFile(filename: String, fileExtension ext: String) async throws -> String {
        return try await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(forResource: filename, withExtension: ext) else {
                throw NSError(domain: "LegalDetailViewModel", code: 404, userInfo: [NSLocalizedDescriptionKey: "File not found."])
            }
            return try String(contentsOf: url, encoding: .utf8)
        }.value
    }
}
