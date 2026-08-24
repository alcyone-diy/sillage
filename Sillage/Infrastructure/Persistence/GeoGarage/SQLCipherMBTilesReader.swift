//
//  SQLCipherMBTilesReader.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import SQLCipher
import OSLog

/// High-performance MBTiles reader delegating connection lifecycle and bounded pooling to `SQLiteConnectionPool`.
final class SQLCipherMBTilesReader: SQLCipherMBTilesReaderProtocol, Sendable {

  private let pool: SQLiteConnectionPool

  // MARK: - Initializer

  /// Initializes the reader and pre-warms the SQLite connection pool.
  /// - Parameters:
  ///   - fileURL: Local `.mbtiles` file path.
  ///   - encryptionKey: Key derived from partner secret and customer ID.
  ///   - maxConnections: Strict upper bound of concurrent open database handles (default 6).
  ///   - prewarmCount: Number of connections to open immediately during init (default 2).
  /// - Throws: `CaasError.fileSystemError` or `CaasError.decryptionFailed`.
  init(
    fileURL: URL,
    encryptionKey: String,
    maxConnections: Int = 6,
    prewarmCount: Int = 2
  ) throws(CaasError) {
    self.pool = try SQLiteConnectionPool(
      fileURL: fileURL,
      encryptionKey: encryptionKey,
      maxConnections: maxConnections,
      prewarmCount: prewarmCount
    )
  }

  // MARK: - Tile Retrieval

  func tile(z: Int, x: Int, y: Int) async -> Data? {
    guard z >= 0, x >= 0, y >= 0 else { return nil }

    let handle: SQLiteConnectionHandle
    do {
      handle = try await pool.borrow()
    } catch {
      Logger.caas.error("Failed to borrow SQLite connection from pool: \(error.localizedDescription, privacy: .public)")
      return nil
    }

    // Short-circuit disk I/O if MapLibre or caller cancelled the task while waiting in the pool
    guard !Task.isCancelled else {
      await pool.returnHandle(handle)
      return nil
    }

    // Convert XYZ row (top-left origin) to TMS row (bottom-left origin)
    let tmsY = (1 << z) - 1 - y

    let statement = handle.statement
    sqlite3_bind_int(statement, 1, Int32(z))
    sqlite3_bind_int(statement, 2, Int32(x))
    sqlite3_bind_int(statement, 3, Int32(tmsY))

    var tileData: Data? = nil
    if sqlite3_step(statement) == SQLITE_ROW {
      if let blobPointer = sqlite3_column_blob(statement, 0) {
        let byteCount = Int(sqlite3_column_bytes(statement, 0))
        if byteCount > 0 {
          tileData = Data(bytes: blobPointer, count: byteCount)
        }
      }
    }

    await pool.returnHandle(handle)
    return tileData
  }

  // MARK: - Close

  func close() async {
    await pool.close()
  }
}
