//
//  BackgroundTaskRunner.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-14.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import UIKit
import OSLog
import os

// MARK: - Internal Logger

// BackgroundTaskToken must not rely on the project-internal Logger extension
// since it is compiled without the rest of the module in isolation.
// We define a module-scoped logger here, consistent with Logger+Sillage.swift.
private let taskLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "sillage", category: "system")

// MARK: - BackgroundTaskToken

/// A RAII token that keeps the app alive in the iOS background.
///
/// Acquire via `BackgroundTaskRunner.acquireToken(name:)` for long-running
/// operations (e.g., a map download) where you need to hold the background
/// assertion open-endedly and release it yourself via `invalidate()`.
///
/// `deinit` acts as a guaranteed safety net using `OSAllocatedUnfairLock`
/// to avoid leaking the background assertion if the token is dropped
/// without an explicit `invalidate()` call.
@MainActor
public final class BackgroundTaskToken {
  // OSAllocatedUnfairLock lets deinit (nonisolated) safely read and clear
  // the task ID without a MainActor hop, per AGENTS.md rules.
  private let lock = OSAllocatedUnfairLock(initialState: UIBackgroundTaskIdentifier.invalid)

  fileprivate init(name: String) {
    let id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      taskLogger.warning("iOS background time expired: \(name, privacy: .public).")
      // The expiration handler is delivered on an unspecified thread — use an
      // async Task hop instead of assumeIsolated to avoid a potential crash.
      Task { @MainActor [weak self] in self?.invalidate() }
    }
    lock.withLock { $0 = id }
  }

  /// Ends the background task. Safe to call multiple times (idempotent).
  public func invalidate() {
    let id = lock.withLock { state -> UIBackgroundTaskIdentifier in
      let current = state
      state = .invalid
      return current
    }
    guard id != .invalid else { return }
    UIApplication.shared.endBackgroundTask(id)
  }

  /// Safety net: ends the background task if the token is dropped without
  /// an explicit `invalidate()`, preventing background-assertion leaks.
  nonisolated deinit {
    let id = lock.withLock { state -> UIBackgroundTaskIdentifier in
      let current = state
      state = .invalid
      return current
    }
    guard id != .invalid else { return }
    // deinit is nonisolated and can run on any thread. assumeIsolated would
    // crash if not already on the MainActor. An async Task hop is the only
    // safe way to call @MainActor-isolated UIApplication.shared from here.
    // Fire-and-forget is acceptable: the OS reclaims the assertion regardless
    // at expiry, so there is no correctness risk in the gap.
    Task { @MainActor in UIApplication.shared.endBackgroundTask(id) }
  }
}

// MARK: - BackgroundTaskRunner

/// Convenience entry points for UIKit background tasks.
@MainActor
public enum BackgroundTaskRunner {

  /// Acquires a persistent background task token (RAII pattern).
  /// The caller owns the token and must call `invalidate()` when done.
  /// `deinit` of the token is a guaranteed fallback.
  ///
  /// Use this for long-running operations that outlive a single async closure
  /// (e.g., a map tile download driven by an external SDK).
  public static func acquireToken(name: String) -> BackgroundTaskToken {
    BackgroundTaskToken(name: name)
  }

  /// Runs `operation` inside a background task and ends it automatically
  /// when the closure returns. Use for short fire-and-forget work.
  public static func execute(
    name: String,
    priority: TaskPriority = .medium,
    operation: @escaping @Sendable () async -> Void
  ) {
    let token = BackgroundTaskToken(name: name)
    Task.detached(priority: priority) {
      await operation()
      await token.invalidate()
    }
  }

  /// Runs `operation` inside a background task, waits for it, then ends
  /// the task. Use for awaitable short work that must survive backgrounding.
  public static func executeAndWait<T: Sendable>(
    name: String,
    operation: @escaping @Sendable () async throws -> T
  ) async rethrows -> T {
    let token = BackgroundTaskToken(name: name)
    let result = try await operation()
    token.invalidate()
    return result
  }
}
