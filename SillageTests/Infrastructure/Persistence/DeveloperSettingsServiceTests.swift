//
//  DeveloperSettingsServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
@testable import Sillage

@MainActor
struct DeveloperSettingsServiceTests {

  private func makeTestDefaults() -> UserDefaults {
    let suite = "test.developersettings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }

  @Test("Defaults are properly initialized")
  func testDefaultValues() {
    let defaults = makeTestDefaults()
    let service = DeveloperSettingsService(defaults: defaults)

    #expect(service.cogSogCalculationSource == .sillage)
    #expect(service.noiseMultiplier == 0.35)
    #expect(service.velocityWindowDuration == 4.0)
    #expect(service.cogDampingDuration == 4.0)
  }

  @Test("Persisting values updates UserDefaults")
  func testPersistence() {
    let defaults = makeTestDefaults()
    let service = DeveloperSettingsService(defaults: defaults)

    service.cogSogCalculationSource = .iOS
    service.noiseMultiplier = 2.5
    service.velocityWindowDuration = 2.5
    service.cogDampingDuration = 0.0

    #expect(service.cogSogCalculationSource == .iOS)
    #expect(service.noiseMultiplier == 2.5)
    #expect(service.velocityWindowDuration == 2.5)
    #expect(service.cogDampingDuration == 0.0)

    // Re-instantiate from same defaults
    let reloaded = DeveloperSettingsService(defaults: defaults)
    #expect(reloaded.cogSogCalculationSource == .iOS)
    #expect(reloaded.noiseMultiplier == 2.5)
    #expect(reloaded.velocityWindowDuration == 2.5)
    #expect(reloaded.cogDampingDuration == 0.0)
  }

  @Test("Reset restores default settings")
  func testResetAllToDefaults() {
    let defaults = makeTestDefaults()
    let service = DeveloperSettingsService(defaults: defaults)

    service.cogSogCalculationSource = .iOS
    service.noiseMultiplier = 3.0
    service.velocityWindowDuration = 8.0
    service.cogDampingDuration = 1.0

    service.resetAllToDefaults()

    #expect(service.cogSogCalculationSource == .sillage)
    #expect(service.noiseMultiplier == 0.35)
    #expect(service.velocityWindowDuration == 4.0)
    #expect(service.cogDampingDuration == 4.0)
  }
}
