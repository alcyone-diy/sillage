//
//  SettingsViewModel.swift
//  Alcyone Sillage
//

import Foundation
import Observation

@Observable
class SettingsViewModel {
    var legalDocuments: [LegalDocument] = []

    init() {
        self.legalDocuments = [
            LegalDocument(
                title: "Maritime Navigation Warning",
                content: "WARNING: Alcyone Sillage is an electronic navigational aid designed for situational awareness only. It must not be used as the primary means of navigation. This application does not replace official government charts, official notices to mariners, or prudent seamanship. The captain of the vessel assumes all responsibility and liability for the safety of the ship and its crew. Never rely on a single source of information and always maintain a proper visual lookout."
            ),
            LegalDocument(
                title: "Alcyone Sillage (MIT License)",
                content: Self.loadText(filename: "License_MIT")
            ),
            LegalDocument(
                title: "MapLibre GL Native (BSD 2-Clause License)",
                content: Self.loadText(filename: "License_MapLibre")
            )
        ]
    }

    private static func loadText(filename: String) -> String {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "txt") else {
            return "License text not found."
        }
        do {
            return try String(contentsOf: url)
        } catch {
            return "License text not found."
        }
    }
}
