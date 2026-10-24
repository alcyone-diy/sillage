//
//  AppViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-24.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class AppViewModelTests: XCTestCase {

  func testGloveModeUpdatesPreferencesAndThemes() {
    let prefs = MockPreferencesService()
    prefs.gloveModeEnabled = false
    let viewModel = AppViewModel(preferencesService: prefs)

    XCTAssertFalse(viewModel.isGloveModeEnabled)
    XCTAssertFalse(viewModel.marineTheme.isGloveMode)
    XCTAssertEqual(viewModel.marineUIStyle, .standard)

    viewModel.isGloveModeEnabled = true
    XCTAssertTrue(prefs.gloveModeEnabled)
    XCTAssertTrue(viewModel.marineTheme.isGloveMode)
    XCTAssertEqual(viewModel.marineUIStyle, .gloveMode)
  }

  func testNotificationSetsPendingIntentWhenReady() {
    let viewModel = AppViewModel(preferencesService: MockPreferencesService())
    viewModel.isReady = true

    viewModel.handleNotification(identifier: NotificationIntent.anchorDragging.rawValue)
    XCTAssertEqual(viewModel.pendingNotificationIntent, .anchorDragging)
  }

  func testNotificationDeferredUntilReady() {
    let viewModel = AppViewModel(preferencesService: MockPreferencesService())
    viewModel.isReady = false

    viewModel.handleNotification(identifier: NotificationIntent.anchorDragging.rawValue)
    XCTAssertNil(viewModel.pendingNotificationIntent)

    viewModel.isReady = true
    viewModel.processDeferredIntent()

    XCTAssertEqual(viewModel.pendingNotificationIntent, .anchorDragging)
  }

  func testSilenceActionNotificationDoesNotSetPendingIntent() {
    let viewModel = AppViewModel(preferencesService: MockPreferencesService())
    viewModel.isReady = true

    viewModel.handleNotification(identifier: NotificationIntent.anchorActionSilence.rawValue)
    XCTAssertNil(viewModel.pendingNotificationIntent)
  }

  func testOtherNotificationSetsPendingIntent() {
    let viewModel = AppViewModel(preferencesService: MockPreferencesService())
    viewModel.isReady = true

    viewModel.handleNotification(identifier: NotificationIntent.barometerDrop.rawValue)
    XCTAssertEqual(viewModel.pendingNotificationIntent, .barometerDrop)
  }
}
