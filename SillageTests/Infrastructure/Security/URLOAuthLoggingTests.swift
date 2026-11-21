//
//  URLOAuthLoggingTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

final class URLOAuthLoggingTests: XCTestCase {

  func testOAuthStructureSummaryRedactsQueryAndFragment() throws {
    let url = try XCTUnwrap(
      URL(string: "https://accounts.geogarage.com/o/authorize/?client_id=clientXYZ&state=csrf456&code_challenge=chal789#frag=secretFrag")
    )

    let summary = url.oauthStructureSummary

    XCTAssertEqual(summary, "scheme=https host=accounts.geogarage.com path=/o/authorize")
    XCTAssertFalse(summary.contains("clientXYZ"))
    XCTAssertFalse(summary.contains("csrf456"))
    XCTAssertFalse(summary.contains("chal789"))
    XCTAssertFalse(summary.contains("secretFrag"))
  }

  func testOAuthCallbackSummaryReportsPresenceWithoutLeakingSecrets() throws {
    let url = try XCTUnwrap(
      URL(string: "https://sillage.alcyone.app/oauth/callback?code=secret123&state=csrf456&extra=leakMe#access_token=tok999")
    )

    let summary = url.oauthCallbackSummary

    XCTAssertEqual(summary, "scheme=https host=sillage.alcyone.app path=/oauth/callback hasCode=true hasState=true")
    XCTAssertFalse(summary.contains("secret123"))
    XCTAssertFalse(summary.contains("csrf456"))
    XCTAssertFalse(summary.contains("leakMe"))
    XCTAssertFalse(summary.contains("tok999"))
  }

  func testOAuthCallbackSummaryHandlesMissingOrEmptyParameters() throws {
    let url = try XCTUnwrap(URL(string: "https://sillage.alcyone.app/oauth/callback?code=&error=access_denied"))

    let summary = url.oauthCallbackSummary

    XCTAssertEqual(summary, "scheme=https host=sillage.alcyone.app path=/oauth/callback hasCode=false hasState=false")
    XCTAssertFalse(summary.contains("access_denied"))
  }
}
