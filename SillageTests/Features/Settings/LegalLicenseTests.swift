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
  func testSettingsViewModelDoesNotIncludeRemovedSolarLicense() {
    let viewModel = SettingsViewModel()

    let solarDoc = viewModel.thirdPartyLicenseDocuments.first {
      $0.filename == "License_Solar"
    }

    XCTAssertNil(solarDoc, "Removed Solar SPM dependency license should not be present")
  }
}
