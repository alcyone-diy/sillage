//
//  GeoGarageLoginViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import SwiftUI
@testable import Sillage


@MainActor
final class GeoGarageLoginViewModelTests: XCTestCase {

  func testAuthenticationFailureSetsErrorMessage() async {
    // Arrange
    let mockAuthService = MockGeoGarageAuthService()
    mockAuthService.shouldFailAuthenticate = true
    let viewModel = GeoGarageLoginViewModel(authService: mockAuthService)

    viewModel.username = "testuser"
    viewModel.password = "testpass"

    // Act
    viewModel.login()
    
    // Await the task cleanly instead of polling
    await viewModel.loginTask?.value

    // Assert
    XCTAssertNotNil(viewModel.errorMessage, "An error message should be set on auth failure")
    
    _ = viewModel // Keep strong reference alive
  }

}
