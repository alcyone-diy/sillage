//
//  TrackPersistenceWriter.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog
import GRDB

/// A dedicated writer that handles high-frequency track point buffering and asynchronous database writes,
/// ensuring the Main Thread is never blocked during persistence operations.
public final class TrackPersistenceWriter: Sendable {
  private let databaseManager: DatabaseManager
  private enum Action: Sendable {
    case insertSession(TrackSessionRecord)
    case appendPoint(TrackPointRecord)
    case flush(sessionUpdate: TrackSessionRecord?, onCompletion: (@Sendable () -> Void)?)
    case finish(onCompletion: @Sendable () -> Void)
  }
  
  private let continuation: AsyncStream<Action>.Continuation
  private let persistenceTask: Task<Void, Never>
  
  public init(databaseManager: DatabaseManager) {
    self.databaseManager = databaseManager
    
    let (stream, continuation) = AsyncStream.makeStream(of: Action.self)
    self.continuation = continuation
    
    self.persistenceTask = Task.detached(priority: .utility) { [databaseManager] in
      var buffer: [TrackPointRecord] = []
      
      for await action in stream {
        do {
          switch action {
          case .insertSession(let session):
            try await databaseManager.writer.write { db in
              try session.insert(db)
            }
            
          case .appendPoint(let point):
            buffer.append(point)
            
          case .flush(let sessionUpdate, let onCompletion):
            if !buffer.isEmpty || sessionUpdate != nil {
              let batch = buffer
              buffer.removeAll()
              try await databaseManager.writer.write { db in
                try batch.forEach { try $0.insert(db) }
                if let sessionUpdate {
                  try sessionUpdate.update(db)
                }
              }
            }
            onCompletion?()
            
          case .finish(let onCompletion):
            if !buffer.isEmpty {
              let batch = buffer
              buffer.removeAll()
              try await databaseManager.writer.write { db in
                try batch.forEach { try $0.insert(db) }
              }
            }
            onCompletion()
          }
        } catch {
          Logger.database.error("TrackPersistenceWriter failed to execute database action: \(error.localizedDescription, privacy: .public)")
          if case .flush(_, let onCompletion) = action {
            onCompletion?()
          } else if case .finish(let onCompletion) = action {
            onCompletion()
          }
        }
      }
    }
  }
  
  deinit {
    continuation.finish()
  }
  
  public func insertSession(_ session: TrackSessionRecord) {
    continuation.yield(.insertSession(session))
  }
  
  public func appendPoint(_ point: TrackPointRecord) {
    continuation.yield(.appendPoint(point))
  }
  
  /// Asynchronously waits for the buffer to be flushed to the database.
  public func flush(sessionUpdate: TrackSessionRecord?) async {
    await withCheckedContinuation { checkedContinuation in
      let result = continuation.yield(.flush(sessionUpdate: sessionUpdate, onCompletion: {
        checkedContinuation.resume()
      }))
      
      switch result {
      case .enqueued:
        break // The background task will call onCompletion
      case .dropped, .terminated:
        checkedContinuation.resume()
      @unknown default:
        checkedContinuation.resume()
      }
    }
  }
  
  /// Fire-and-forget flush.
  public func flushAsync(sessionUpdate: TrackSessionRecord?) {
    continuation.yield(.flush(sessionUpdate: sessionUpdate, onCompletion: nil))
  }
  
  public func finish() async {
    await withCheckedContinuation { checkedContinuation in
      let result = continuation.yield(.finish(onCompletion: {
        checkedContinuation.resume()
      }))
      
      switch result {
      case .enqueued:
        break // The background task will call onCompletion
      case .dropped, .terminated:
        checkedContinuation.resume()
      @unknown default:
        checkedContinuation.resume()
      }
    }
    continuation.finish()
    _ = await persistenceTask.value
  }
}
