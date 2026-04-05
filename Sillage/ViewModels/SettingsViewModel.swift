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
                filename: "License_MIT",
                fileExtension: "txt"
            ),
            LegalDocument(
                title: "MapLibre GL Native (BSD 2-Clause License)",
                filename: "License_MapLibre",
                fileExtension: "txt"
            )
        ]
    }
}
