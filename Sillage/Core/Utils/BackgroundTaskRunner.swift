//
//  TaskCancellable.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-14.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import UIKit
import OSLog

// Creates an async task to make sure it won't be killed by iOS.
@MainActor
private final class BackgroundTaskTracker {
  private var taskId: UIBackgroundTaskIdentifier = .invalid

  func begin(name: String) {
    taskId = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      Logger.system.warning("iOS background time expired before flush completed: \(name).")
      MainActor.assumeIsolated {
        self?.end()
      }
    }
  }

  func end() {
    if taskId != .invalid {
      UIApplication.shared.endBackgroundTask(taskId)
      taskId = .invalid
    }
  }
}

// Public entry point.
@MainActor
public enum BackgroundTaskRunner {
  public static func execute(name: String, priority: TaskPriority = .utility, operation: @escaping @Sendable () async -> Void) {
    let tracker = BackgroundTaskTracker()
    tracker.begin(name: name)

    Task.detached(priority: priority) {
      await operation()
      await tracker.end()
    }
  }

  public static func executeAndWait<T: Sendable>(name: String, operation: @escaping @Sendable () async throws -> T) async rethrows -> T {
    let tracker = BackgroundTaskTracker()
    tracker.begin(name: name)
    
    let result = try await operation()
    
    tracker.end()
    return result
  }
}
