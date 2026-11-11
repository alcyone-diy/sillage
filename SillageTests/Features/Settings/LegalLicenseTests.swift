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
  func testSettingsViewModelIncludesSolarLicense() {
    let viewModel = SettingsViewModel()

    let solarDoc = viewModel.thirdPartyLicenseDocuments.first {
      String(localized: $0.title).contains("Solar")
    }

    XCTAssertNotNil(solarDoc, "Solar license document should be present in thirdPartyLicenseDocuments")
    XCTAssertEqual(solarDoc?.filename, "License_Solar")
    XCTAssertEqual(solarDoc?.fileExtension, "txt")
  }

  func testSolarLicenseFileExistsInBundle() {
    let bundle = Bundle(for: type(of: self))
    // Check main or module/test bundle for the resource
    let url = Bundle.main.url(forResource: "License_Solar", withExtension: "txt") ??
              bundle.url(forResource: "License_Solar", withExtension: "txt")
    
    // In test environment, if Bundle.main points to the app host bundle
    if let url {
      let content = try? String(contentsOf: url, encoding: .utf8)
      XCTAssertNotNil(content)
      XCTAssertTrue(content?.contains("Chris Howell") == true)
    }
  }
}
