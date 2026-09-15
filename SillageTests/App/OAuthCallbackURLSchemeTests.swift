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

  func testInfoPlistDeclaresTheOAuthCallbackScheme() {
    let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
    let schemes = urlTypes.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
    XCTAssertTrue(schemes.contains(AppConstants.GeoGarage.oauthCallbackScheme), "schemes: \(schemes)")
  }

  func testRedirectURIUsesTheDeclaredScheme() throws {
    let redirect = try XCTUnwrap(URL(string: AppConstants.GeoGarage.oauthRedirectURI))
    XCTAssertEqual(redirect.scheme, AppConstants.GeoGarage.oauthCallbackScheme)
    XCTAssertEqual(redirect.host, "oauth2")
    XCTAssertEqual(redirect.path, "/callback")
  }

  func testOAuthCallbackURLIsIgnoredByChartImport() throws {
    let viewModel = AppViewModel(preferencesService: PreferencesService())
    let url = try XCTUnwrap(URL(string: "\(AppConstants.GeoGarage.oauthRedirectURI)?code=abc&state=xyz"))
    viewModel.handleIncomingURL(url)
    XCTAssertFalse(viewModel.showImportError)
    XCTAssertNil(viewModel.importError)
  }
}
