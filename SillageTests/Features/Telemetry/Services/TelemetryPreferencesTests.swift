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
  private var userDefaults: UserDefaults!
  private let suiteName = "TelemetryPreferencesTestsSuite"

  override func setUp() {
    super.setUp()
    userDefaults = UserDefaults(suiteName: suiteName)
    userDefaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    userDefaults.removePersistentDomain(forName: suiteName)
    userDefaults = nil
    super.tearDown()
  }

  func testDefaultMetrics_LoadedWhenNoSavedPreferencesExist() {
    let preferences = TelemetryPreferences(userDefaults: userDefaults)
    XCTAssertEqual(preferences.activeMetrics, TelemetryPreferences.defaultMetrics)
    XCTAssertEqual(preferences.activeMetrics, [.sog, .cog, .btw, .rng])
  }

  func testSaveAndLoadActiveMetrics_PersistsCorrectly() {
    let preferences = TelemetryPreferences(userDefaults: userDefaults)
    let customMetrics: [TelemetryMetric] = [.sog, .cog, .battery]

    preferences.activeMetrics = customMetrics

    // Re-instantiate TelemetryPreferences with the same UserDefaults to verify persistence
    let reloadedPreferences = TelemetryPreferences(userDefaults: userDefaults)
    XCTAssertEqual(reloadedPreferences.activeMetrics, customMetrics)
  }

  func testResetToDefaults_RestoresDefaultConfiguration() {
    let preferences = TelemetryPreferences(userDefaults: userDefaults)
    preferences.activeMetrics = [.battery, .xte]

    XCTAssertEqual(preferences.activeMetrics, [.battery, .xte])

    preferences.resetToDefaults()
    XCTAssertEqual(preferences.activeMetrics, TelemetryPreferences.defaultMetrics)
  }
}
