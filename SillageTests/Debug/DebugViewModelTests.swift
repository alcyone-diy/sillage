//
//  DebugViewModelTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

#if DEBUG
import XCTest
@testable import Sillage

@MainActor
final class DebugViewModelTests: XCTestCase {

  func testInvalidateGeoGarageTokenSavesInvalidTokensAsynchronously() async throws {
    let mockKeychain = MockKeychainManager()
    let viewModel = DebugViewModel(keychainManager: mockKeychain)

    await viewModel.invalidateGeoGarageToken()

    let accessToken = try await mockKeychain.retrieveToken(for: GeoGarageKeychainKeys.accessToken)
    let refreshToken = try await mockKeychain.retrieveToken(for: GeoGarageKeychainKeys.refreshToken)
    XCTAssertEqual(accessToken, "invalid_debug_token")
    XCTAssertEqual(refreshToken, "invalid_debug_refresh_token")
  }

  func testInvalidateGeoGarageTokenHandlesKeychainErrorGracefully() async throws {
    let mockKeychain = MockKeychainManager(initialTokens: [
      GeoGarageKeychainKeys.accessToken: "original_access",
      GeoGarageKeychainKeys.refreshToken: "original_refresh"
    ])
    mockKeychain.setStubbedError(.unexpectedStatus(errSecAuthFailed))
    let viewModel = DebugViewModel(keychainManager: mockKeychain)

    await viewModel.invalidateGeoGarageToken()

    mockKeychain.setStubbedError(nil)
    let accessToken = try await mockKeychain.retrieveToken(for: GeoGarageKeychainKeys.accessToken)
    let refreshToken = try await mockKeychain.retrieveToken(for: GeoGarageKeychainKeys.refreshToken)
    XCTAssertEqual(accessToken, "original_access")
    XCTAssertEqual(refreshToken, "original_refresh")
  }
}
#endif
