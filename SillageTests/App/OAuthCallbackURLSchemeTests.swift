//
//  OAuthCallbackURLSchemeTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class OAuthCallbackURLSchemeTests: XCTestCase {

  func testRedirectURIUsesHTTPSCallback() throws {
    let redirect = try XCTUnwrap(URL(string: AppConstants.GeoGarage.oauthRedirectURI))
    XCTAssertEqual(redirect.scheme, "https")
    XCTAssertEqual(redirect.host, AppConstants.GeoGarage.oauthCallbackHost)
    XCTAssertEqual(redirect.path, AppConstants.GeoGarage.oauthCallbackPath)
  }

  func testOAuthCallbackURLIsIgnoredByChartImport() throws {
    let viewModel = AppViewModel(preferencesService: PreferencesService())
    let url = try XCTUnwrap(URL(string: "\(AppConstants.GeoGarage.oauthRedirectURI)?code=abc&state=xyz"))
    viewModel.handleIncomingURL(url)
    XCTAssertFalse(viewModel.showImportError)
    XCTAssertNil(viewModel.importError)
  }

  func testNonHTTPSCallbackURLIsNotIgnoredByChartImport() throws {
    let viewModel = AppViewModel(preferencesService: PreferencesService())
    let url = try XCTUnwrap(URL(string: "http://\(AppConstants.GeoGarage.oauthCallbackHost)\(AppConstants.GeoGarage.oauthCallbackPath)?code=abc&state=xyz"))
    viewModel.handleIncomingURL(url)
    XCTAssertTrue(viewModel.showImportError)
  }
}
