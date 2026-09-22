//
//  TestWaitUtilities.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Testing

struct TimeoutError: Error, CustomStringConvertible, Sendable {
  let timeout: Duration
  var description: String { "waitUntil timed out after \(timeout)" }
}

@MainActor
func waitUntil(
  _ condition: @escaping @MainActor () -> Bool,
  timeout: Duration = .seconds(2),
  pollInterval: Duration = .milliseconds(20)
) async throws {
  let start = ContinuousClock.now
  while !condition() {
    if ContinuousClock.now - start > timeout {
      throw TimeoutError(timeout: timeout)
    }
    try await Task.sleep(for: pollInterval)
  }
}
