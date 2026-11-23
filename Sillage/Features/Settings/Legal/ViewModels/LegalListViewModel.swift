//
//  LegalListViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation

@MainActor
@Observable
final class LegalListViewModel {
  let navigationWarningDocument: LegalDocument
  let sillageLicenseDocument: LegalDocument
  let thirdPartyLicenseDocuments: [LegalDocument]

  init() {
    navigationWarningDocument = LegalDocument.document(for: .navigationWarning)
    sillageLicenseDocument = LegalDocument.document(for: .sillageLicense)
    thirdPartyLicenseDocuments = LegalDocument.thirdPartyDocumentIDs
      .map(LegalDocument.document(for:))
      .sorted {
        let title1 = String(localized: $0.title)
        let title2 = String(localized: $1.title)
        return title1.localizedStandardCompare(title2) == .orderedAscending
      }
  }
}
