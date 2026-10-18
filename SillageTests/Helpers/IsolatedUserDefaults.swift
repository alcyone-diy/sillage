//
//  IsolatedUserDefaults.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-10-18.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Encapsulates an ephemeral, uniquely-named `UserDefaults` suite to prevent any test
/// from reading or writing into `UserDefaults.standard` on the host device.
final class IsolatedUserDefaults: @unchecked Sendable {
  let defaults: UserDefaults
  let suiteName: String

  init(prefix: String = "SillageTests") {
    let suite = "\(prefix)-\(UUID().uuidString)"
    self.suiteName = suite
    guard let defaults = UserDefaults(suiteName: suite) else {
      fatalError("Failed to instantiate isolated UserDefaults for suite: \(suite)")
    }
    defaults.removePersistentDomain(forName: suite)
    self.defaults = defaults
  }

  func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
  }

  deinit {
    defaults.removePersistentDomain(forName: suiteName)
  }
}

/// Convenience factory for creating an isolated ephemeral UserDefaults suite.
func makeIsolatedUserDefaults(prefix: String = "SillageTests") -> (defaults: UserDefaults, suiteName: String) {
  let isolated = IsolatedUserDefaults(prefix: prefix)
  return (isolated.defaults, isolated.suiteName)
}
