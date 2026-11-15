//
//  AnchorStateStore.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import os

/// State container representing the persistent anchor watch session state.
nonisolated public struct AnchorSessionData: Codable, Sendable, Equatable {
  public var activeWatch: AnchorWatch?
  public var status: AnchorStatus
  public var triggerReason: AnchorTriggerReason?

  public init(
    activeWatch: AnchorWatch? = nil,
    status: AnchorStatus = .inactive,
    triggerReason: AnchorTriggerReason? = nil
  ) {
    self.activeWatch = activeWatch
    self.status = status
    self.triggerReason = triggerReason
  }
}

nonisolated public protocol AnchorStateStoreProtocol: Sendable {
  func loadSession() -> AnchorSessionData
  func saveSession(_ session: AnchorSessionData)
}

nonisolated public final class AnchorStateStore: AnchorStateStoreProtocol, Sendable {
  private enum PersistenceCommand: Sendable {
    case save(AnchorSessionData)
    case flush(CheckedContinuation<Void, Never>)
  }

  private let stateLock: OSAllocatedUnfairLock<AnchorSessionData>
  private let continuation: AsyncStream<PersistenceCommand>.Continuation
  private let persistenceTask: Task<Void, Never>

  public init(fileManager: FileManager = FileManager(), directoryURL: URL? = nil) {
    let appSupportDir: URL
    if let directoryURL {
      appSupportDir = directoryURL
    } else {
      let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      appSupportDir = urls.first?.appendingPathComponent("Sillage", isDirectory: true) ?? fileManager.temporaryDirectory
    }
    
    try? fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    let url = appSupportDir.appendingPathComponent("anchor_session.json")

    var initialData = AnchorSessionData()
    if fileManager.fileExists(atPath: url.path),
       let data = try? Data(contentsOf: url),
       let decoded = try? JSONDecoder().decode(AnchorSessionData.self, from: data) {
      initialData = decoded
    }
    self.stateLock = OSAllocatedUnfairLock(initialState: initialData)

    let (stream, continuation) = AsyncStream.makeStream(of: PersistenceCommand.self)
    self.continuation = continuation

    // Single FIFO background consumer guarantees chronological write ordering without blocking the caller.
    self.persistenceTask = Task.detached(priority: .medium) {
      let encoder = JSONEncoder()
      for await command in stream {
        switch command {
        case .save(let session):
          do {
            let data = try encoder.encode(session)
            try data.write(to: url, options: .atomic)
          } catch {
            Logger.anchor.error("Failed to persist anchor session state to disk: \(error.localizedDescription, privacy: .public)")
          }
        case .flush(let completion):
          completion.resume()
        }
      }
    }
  }

  deinit {
    continuation.finish()
  }

  public func loadSession() -> AnchorSessionData {
    stateLock.withLock { $0 }
  }

  public func saveSession(_ session: AnchorSessionData) {
    stateLock.withLock { $0 = session }
    continuation.yield(.save(session))
  }

  /// Suspends until all previously enqueued disk writes have completed.
  func flush() async {
    await withCheckedContinuation { completion in
      let yieldResult = continuation.yield(.flush(completion))
      if case .terminated = yieldResult {
        completion.resume()
      }
    }
  }
}
