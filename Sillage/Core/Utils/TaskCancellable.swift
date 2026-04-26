//
//  TaskCancellable.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 15/04/2026.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

/// A thread-safe wrapper that automatically cancels an underlying Swift Concurrency Task upon deallocation.
/// This is particularly useful for managing task lifecycles within `@MainActor` isolated classes
/// without violating Swift 6 strict concurrency rules during `deinit`.
public final class TaskCancellable: Sendable {
  private let task: Task<Void, Never>

  /// Initializes the wrapper with the given task.
  /// - Parameter task: The asynchronous task to manage and automatically cancel.
  public init(_ task: Task<Void, Never>) {
    self.task = task
  }

  deinit {
    task.cancel()
  }

  /// Triggers an explicit manual cancellation of the task.
  /// Call this method if you need to stop the task immediately before the `TaskCancellable` instance is naturally deallocated.
  public func cancel() {
    task.cancel()
  }
}
