//
//  ChecklistThrottler.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Thread-safe actor responsible for debouncing rapid consecutive taps on checklist items.
/// Prevents excessive SQLite WAL transactions caused by rough seas or wet touchscreen interactions.
public actor ChecklistThrottler {
  private var lastActionTimestamps: [UUID: ContinuousClock.Instant] = [:]
  private let window: Duration
  private var actionCount: Int = 0

  public init(window: Duration = .milliseconds(300)) {
    self.window = window
  }

  /// Evaluates whether an action on a specific checklist item should be processed or dropped as a bounce.
  /// Automatically prunes expired entries every 50 actions to maintain a bounded memory footprint.
  public func shouldProcessAction(for itemId: UUID, clock: ContinuousClock = ContinuousClock()) -> Bool {
    actionCount += 1
    if actionCount.isMultiple(of: 50) {
      pruneExpired(clock: clock)
    }

    let now = clock.now
    if let lastTime = lastActionTimestamps[itemId] {
      if now - lastTime < window {
        return false // Debounced bounce
      }
    }
    lastActionTimestamps[itemId] = now
    return true
  }

  /// Removes timestamps that fall outside the active debouncing window.
  private func pruneExpired(clock: ContinuousClock) {
    let now = clock.now
    lastActionTimestamps = lastActionTimestamps.filter { _, timestamp in
      now - timestamp < window
    }
  }
}
