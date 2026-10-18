//
//  TelemetryPreferencesTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class TelemetryPreferencesTests: XCTestCase {
  private var isolatedDefaults: IsolatedUserDefaults?

  override func setUp() {
    super.setUp()
    isolatedDefaults = IsolatedUserDefaults(prefix: "TelemetryPreferencesTests")
  }

  override func tearDown() {
    isolatedDefaults?.tearDown()
    isolatedDefaults = nil
    super.tearDown()
  }

  func testDefaultMetrics_LoadedWhenNoSavedPreferencesExist() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let preferences = TelemetryPreferences(userDefaults: defaults)
    XCTAssertEqual(preferences.activeMetrics, TelemetryPreferences.defaultMetrics)
    XCTAssertEqual(preferences.activeMetrics, [.sog, .cog, .btw, .rng])
  }

  func testSaveAndLoadActiveMetrics_PersistsCorrectly() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let preferences = TelemetryPreferences(userDefaults: defaults)
    let customMetrics: [TelemetryMetric] = [.sog, .cog, .battery]

    preferences.activeMetrics = customMetrics

    // Re-instantiate TelemetryPreferences with the same UserDefaults to verify persistence
    let reloadedPreferences = TelemetryPreferences(userDefaults: defaults)
    XCTAssertEqual(reloadedPreferences.activeMetrics, customMetrics)
  }

  func testResetToDefaults_RestoresDefaultConfiguration() throws {
    let defaults = try XCTUnwrap(isolatedDefaults?.defaults)
    let preferences = TelemetryPreferences(userDefaults: defaults)
    preferences.activeMetrics = [.battery, .xte]

    XCTAssertEqual(preferences.activeMetrics, [.battery, .xte])

    preferences.resetToDefaults()
    XCTAssertEqual(preferences.activeMetrics, TelemetryPreferences.defaultMetrics)
  }
}
