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
  nonisolated let effectiveRequiresV3Compatibility: Bool
  private let maxConnections: Int

  private var availableHandles: [SQLiteConnectionHandle] = []
  private var totalCreated: Int = 0
  private var waiters: [CheckedContinuation<SQLiteConnectionHandle, any Error>] = []
  private var isClosed: Bool = false

  // MARK: - Initializer

  init(
    fileURL: URL,
    encryptionKey: String,
    requiresV3Compatibility: Bool = false,
    maxConnections: Int = 6,
    prewarmCount: Int = 2
  ) throws(CaasError) {
    guard maxConnections > 0 else {
      throw CaasError.fileSystemError(underlying: "maxConnections must be greater than 0.")
    }
    self.fileURL = fileURL
    self.encryptionKey = encryptionKey
    self.maxConnections = maxConnections

    // Open first connection using adaptive fallback (trying requested mode first, then alternative)
    let (firstHandle, resolvedV3) = try Self.openWithAdaptiveFallback(
      fileURL: fileURL,
      encryptionKey: encryptionKey,
      preferredV3Compatibility: requiresV3Compatibility
    )
    self.effectiveRequiresV3Compatibility = resolvedV3
    self.availableHandles.append(firstHandle)
    self.totalCreated += 1

    // Pre-warm remaining connection handles directly using the resolved compatibility
    let initialCount = min(max(1, prewarmCount), maxConnections)
    for _ in 1..<initialCount {
      let handle = try Self.openAndPrepare(
        fileURL: fileURL,
        encryptionKey: encryptionKey,
        requiresV3Compatibility: resolvedV3
      )
      self.availableHandles.append(handle)
      self.totalCreated += 1
    }

    Logger.caas.info("SQLiteConnectionPool initialized with \(initialCount, privacy: .public)/\(maxConnections, privacy: .public) pre-warmed connection(s) [SQLCipher \(resolvedV3 ? "v3" : "v4", privacy: .public)] for \(fileURL.lastPathComponent, privacy: .public)")
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
      let handle = try Self.openAndPrepare(
        fileURL: fileURL,
        encryptionKey: encryptionKey,
        requiresV3Compatibility: effectiveRequiresV3Compatibility
      )
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

  /// Probes the MBTiles file by attempting to open it with the preferred format.
  /// If HMAC check or decryption fails, seamlessly falls back to the alternative format (v4 <-> v3).
  private static func openWithAdaptiveFallback(
    fileURL: URL,
    encryptionKey: String,
    preferredV3Compatibility: Bool
  ) throws(CaasError) -> (handle: SQLiteConnectionHandle, effectiveRequiresV3: Bool) {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw CaasError.fileSystemError(underlying: "MBTiles file does not exist at \(fileURL.path)")
    }

    let keyData = Data(encryptionKey.utf8)

    // 1. Attempt with preferred format (v4 by default, or v3 if explicitly requested)
    if let result = tryOpen(fileURL: fileURL, keyData: keyData, v3Compatibility: preferredV3Compatibility) {
      return (SQLiteConnectionHandle(db: result.db, statement: result.statement), preferredV3Compatibility)
    }

    // 2. Adaptive Fallback: Attempt with alternative format (v3 if v4 failed, or v4 if v3 failed)
    let fallbackV3Compatibility = !preferredV3Compatibility
    if let fallbackResult = tryOpen(fileURL: fileURL, keyData: keyData, v3Compatibility: fallbackV3Compatibility) {
      Logger.caas.info("Adaptive fallback: opened '\(fileURL.lastPathComponent, privacy: .public)' using SQLCipher \(fallbackV3Compatibility ? "v3" : "v4", privacy: .public) compatibility.")
      return (SQLiteConnectionHandle(db: fallbackResult.db, statement: fallbackResult.statement), fallbackV3Compatibility)
    }

    // 3. Both formats failed HMAC check or decryption
    throw CaasError.decryptionFailed(reason: "Invalid encryption key or corrupt MBTiles database.")
  }

  private static func openAndPrepare(
    fileURL: URL,
    encryptionKey: String,
    requiresV3Compatibility: Bool
  ) throws(CaasError) -> SQLiteConnectionHandle {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw CaasError.fileSystemError(underlying: "MBTiles file does not exist at \(fileURL.path)")
    }

    let keyData = Data(encryptionKey.utf8)

    guard let result = tryOpen(fileURL: fileURL, keyData: keyData, v3Compatibility: requiresV3Compatibility) else {
      throw CaasError.decryptionFailed(reason: "Invalid encryption key or corrupt MBTiles database.")
    }

    return SQLiteConnectionHandle(db: result.db, statement: result.statement)
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
