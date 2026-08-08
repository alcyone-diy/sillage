//
//  XCTestCase+Async.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest

/// Deterministically waits for an asynchronous condition to evaluate to `true` with a specified safety timeout.
/// - Parameters:
///   - timeout: Maximum duration to wait before throwing a `TimeoutError`. Default is 2 seconds.
///   - condition: An asynchronous or synchronous predicate evaluating the target condition.
@MainActor
func waitFor(
  timeout: Duration = .seconds(2),
  condition: @MainActor () -> Bool
) async throws {
  let start = ContinuousClock.now
  while true {
    if condition() { return }
    let elapsed = start.duration(to: ContinuousClock.now)
    if elapsed > timeout {
      struct TimeoutError: Error {}
      throw TimeoutError()
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}

extension XCTestCase {
  /// Deterministically waits for an asynchronous condition to evaluate to `true` with a specified safety timeout.
  @MainActor
  func waitFor(
    timeout: Duration = .seconds(2),
    condition: @MainActor () -> Bool
  ) async throws {
    try await SillageTests.waitFor(timeout: timeout, condition: condition)
  }
}
