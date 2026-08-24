//
//  SQLiteConnectionPool.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import SQLCipher
import OSLog

/// Holds a single open read-only SQLite database connection and its prepared tile query statement.
/// Conforms to `@unchecked Sendable` as it wraps C `OpaquePointer` handles managed exclusively by `SQLiteConnectionPool`.
nonisolated struct SQLiteConnectionHandle: @unchecked Sendable {
  let db: OpaquePointer
  let statement: OpaquePointer
}

/// Actor managing a bounded pool of read-only SQLite/SQLCipher connection handles.
///
/// **Concurrency Architecture**:
/// - Enforces a strict upper bound (`maxConnections`, default 6) to prevent thread starvation and file descriptor leaks.
/// - Pre-warms connection handles upon asynchronous initialization to eliminate SQLCipher key derivation latency at runtime.
/// - Implements FIFO async suspension (`CheckedContinuation`) when all connections are currently in use.
/// - Manages proper cleanup upon `close()`, cancelling any pending waiters and finalizing all database handles.
actor SQLiteConnectionPool {

  private let fileURL: URL
  private let encryptionKey: String
  private let maxConnections: Int

  private var availableHandles: [SQLiteConnectionHandle] = []
  private var totalCreated: Int = 0
  private var waiters: [CheckedContinuation<SQLiteConnectionHandle, any Error>] = []
  private var isClosed: Bool = false

  // MARK: - Initializer

  init(
    fileURL: URL,
    encryptionKey: String,
    maxConnections: Int = 6,
    prewarmCount: Int = 2
  ) throws(CaasError) {
    guard maxConnections > 0 else {
      throw CaasError.fileSystemError(underlying: "maxConnections must be greater than 0.")
    }
    self.fileURL = fileURL
    self.encryptionKey = encryptionKey
    self.maxConnections = maxConnections

    // Pre-warm initial connection handles to eliminate runtime SQLCipher key derivation overhead
    let initialCount = min(max(1, prewarmCount), maxConnections)
    for _ in 0..<initialCount {
      let handle = try Self.openAndPrepare(fileURL: fileURL, encryptionKey: encryptionKey)
      self.availableHandles.append(handle)
      self.totalCreated += 1
    }

    Logger.caas.info("SQLiteConnectionPool initialized with \(initialCount, privacy: .public)/\(maxConnections, privacy: .public) pre-warmed connection(s) for \(fileURL.lastPathComponent, privacy: .public)")
  }

  deinit {
    for handle in availableHandles {
      sqlite3_finalize(handle.statement)
      sqlite3_close_v2(handle.db)
    }
  }

  // MARK: - Connection Borrow & Return

  /// Borrows a connection handle from the pool, asynchronously suspending if all `maxConnections` are currently checked out.
  func borrow() async throws(CaasError) -> SQLiteConnectionHandle {
    if isClosed {
      throw CaasError.fileSystemError(underlying: "Connection pool is closed.")
    }

    // 1. Reuse existing available handle
    if let handle = availableHandles.popLast() {
      return handle
    }

    // 2. Instantiate a new handle up to maxConnections
    if totalCreated < maxConnections {
      let handle = try Self.openAndPrepare(fileURL: fileURL, encryptionKey: encryptionKey)
      totalCreated += 1
      return handle
    }

    // 3. Max connections reached: suspend task until a connection is returned (FIFO queue)
    do {
      return try await withCheckedThrowingContinuation { continuation in
        waiters.append(continuation)
      }
    } catch let error as CaasError {
      throw error
    } catch {
      throw CaasError.fileSystemError(underlying: error.localizedDescription)
    }
  }

  /// Returns a borrowed connection handle back to the pool or hands it off to the next waiting query.
  func returnHandle(_ handle: SQLiteConnectionHandle) {
    if isClosed {
      sqlite3_finalize(handle.statement)
      sqlite3_close_v2(handle.db)
      totalCreated -= 1
      return
    }

    // Reset statement bindings before reusing
    sqlite3_reset(handle.statement)
    sqlite3_clear_bindings(handle.statement)

    // Hand off to the first pending waiter (FIFO)
    if !waiters.isEmpty {
      let nextWaiter = waiters.removeFirst()
      nextWaiter.resume(returning: handle)
      return
    }

    // Otherwise return to the available pool
    availableHandles.append(handle)
  }

  // MARK: - Teardown

  func close() {
    guard !isClosed else { return }
    isClosed = true

    // Resume all pending waiters with error
    for waiter in waiters {
      waiter.resume(throwing: CaasError.fileSystemError(underlying: "Connection pool closed."))
    }
    waiters.removeAll()

    // Finalize all available handles
    for handle in availableHandles {
      sqlite3_finalize(handle.statement)
      sqlite3_close_v2(handle.db)
    }
    availableHandles.removeAll()
    totalCreated = 0

    Logger.caas.info("SQLiteConnectionPool closed.")
  }

  // MARK: - Open & Prepare Helpers

  private static func openAndPrepare(
    fileURL: URL,
    encryptionKey: String
  ) throws(CaasError) -> SQLiteConnectionHandle {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw CaasError.fileSystemError(underlying: "MBTiles file does not exist at \(fileURL.path)")
    }

    let keyData = Data(encryptionKey.utf8)

    // 1. Try opening with SQLCipher 4 (default)
    if let result = tryOpen(fileURL: fileURL, keyData: keyData, v3Compatibility: false) {
      return SQLiteConnectionHandle(db: result.db, statement: result.statement)
    }

    // 2. Fallback: Try opening with SQLCipher 3 legacy compatibility
    if let result = tryOpen(fileURL: fileURL, keyData: keyData, v3Compatibility: true) {
      return SQLiteConnectionHandle(db: result.db, statement: result.statement)
    }

    throw CaasError.decryptionFailed(reason: "Invalid encryption key or corrupt MBTiles database.")
  }

  private static func tryOpen(
    fileURL: URL,
    keyData: Data,
    v3Compatibility: Bool
  ) -> (db: OpaquePointer, statement: OpaquePointer)? {
    var localDB: OpaquePointer?
    guard sqlite3_open_v2(fileURL.path, &localDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let localDB else {
      if let localDB { sqlite3_close_v2(localDB) }
      return nil
    }

    let keyResult = keyData.withUnsafeBytes { rawBuffer in
      sqlite3_key(localDB, rawBuffer.baseAddress, Int32(keyData.count))
    }
    guard keyResult == SQLITE_OK else {
      sqlite3_close_v2(localDB)
      return nil
    }

    if v3Compatibility {
      let v3Pragma = "PRAGMA cipher_compatibility = 3;"
      sqlite3_exec(localDB, v3Pragma, nil, nil, nil)
    }

    var testStmt: OpaquePointer?
    let testSQL = "SELECT count(*) FROM sqlite_master;"
    let prepareTest = sqlite3_prepare_v2(localDB, testSQL, -1, &testStmt, nil)
    let stepTest = prepareTest == SQLITE_OK ? sqlite3_step(testStmt) : SQLITE_ERROR
    sqlite3_finalize(testStmt)

    guard stepTest == SQLITE_ROW || stepTest == SQLITE_DONE else {
      sqlite3_close_v2(localDB)
      return nil
    }

    let tileSQL = "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ? LIMIT 1;"
    var localStmt: OpaquePointer?
    let prepResult = sqlite3_prepare_v2(localDB, tileSQL, -1, &localStmt, nil)
    guard prepResult == SQLITE_OK, let localStmt else {
      sqlite3_close_v2(localDB)
      return nil
    }

    return (localDB, localStmt)
  }
}
