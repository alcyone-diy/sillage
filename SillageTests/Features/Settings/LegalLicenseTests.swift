//
//  LegalLicenseTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

final class LegalLicenseTests: XCTestCase {

  @MainActor
  func testLegalListViewModelDoesNotIncludeRemovedSolarLicense() {
    let viewModel = LegalListViewModel()

    let solarDoc = viewModel.thirdPartyLicenseDocuments.first {
      $0.filename == "License_Solar"
    }

    XCTAssertNil(solarDoc, "Removed Solar SPM dependency license should not be present")
  }

  func testAllLegalDocumentIDsResolveToMatchingDocuments() {
    for documentID in LegalDocumentID.allCases {
      let document = LegalDocument.document(for: documentID)
      XCTAssertEqual(document.id, documentID)
      let hasContentOrFile = document.content != nil || (document.filename != nil && document.fileExtension != nil)
      XCTAssertTrue(hasContentOrFile, "Document \(documentID.rawValue) must have inline content or a bundle file reference")
    }
  }

  @MainActor
  func testLegalListViewModelExposesAllLegalDocumentIDsWithoutDuplicates() {
    let viewModel = LegalListViewModel()
    let exposedIDs = [
      viewModel.navigationWarningDocument.id,
      viewModel.sillageLicenseDocument.id,
    ] + viewModel.thirdPartyLicenseDocuments.map(\.id)

    XCTAssertEqual(
      exposedIDs.count,
      Set(exposedIDs).count,
      "LegalListViewModel must not expose duplicate LegalDocumentIDs"
    )
    XCTAssertEqual(
      Set(exposedIDs),
      Set(LegalDocumentID.allCases),
      "LegalListViewModel must expose every LegalDocumentID case"
    )
  }
}
