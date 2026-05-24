//
//  SettingsViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation

@MainActor
@Observable
class SettingsViewModel {
  let navigationWarningDocument: LegalDocument
  let sillageLicenseDocument: LegalDocument
  var thirdPartyLicenseDocuments: [LegalDocument] = []
  
  init() {
    navigationWarningDocument = LegalDocument(
      title: "Maritime Navigation Warning",
      content: "WARNING: Alcyone Sillage is an electronic navigational aid designed for situational awareness only. It must not be used as the primary means of navigation. This application does not replace official government charts, official notices to mariners, or prudent seamanship. The captain of the vessel assumes all responsibility and liability for the safety of the ship and its crew. Never rely on a single source of information and always maintain a proper visual lookout."
    )
    sillageLicenseDocument = LegalDocument(
        title: "Alcyone Sillage (MIT License)",
        filename: "License_MIT",
        fileExtension: "txt"
      )
    let thirdPartyLicenses = [
      LegalDocument(
        title: "MapLibre GL Native (BSD 2-Clause License)",
        filename: "License_MapLibre",
        fileExtension: "txt"
      ),
      LegalDocument(
        title: "OpenSeaMap (ODbL)",
        filename: "License_OpenSeaMap",
        fileExtension: "txt"
      ),
      LegalDocument(
        title: "GeoGarage Terms of Use",
        filename: "License_GeoGarage",
        fileExtension: "txt"
      ),
      LegalDocument(
        title: "GRDB",
        filename: "License_GRDB",
        fileExtension: "txt"
      ),
      LegalDocument(
        title: "swift-clocks",
        filename: "License_swift-clocks",
        fileExtension: "txt"
      ),
      LegalDocument(
        title: "swift-concurrency-extras",
        filename: "License_swift-concurrency-extras",
        fileExtension: "txt"
      ),
      LegalDocument(
        title: "xctest-dynamic-overlay",
        filename: "License_xctest-dynamic-overlay",
        fileExtension: "txt"
      ),
    ]
    let sortedLicenses = thirdPartyLicenses.sorted {
      let title1 = String(localized: $0.title)
      let title2 = String(localized: $1.title)
      return title1.localizedStandardCompare(title2) == .orderedAscending
    }
    self.thirdPartyLicenseDocuments = sortedLicenses
  }
}
