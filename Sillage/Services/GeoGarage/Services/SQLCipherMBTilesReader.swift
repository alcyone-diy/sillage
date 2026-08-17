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

/// Swift 6 actor that opens an encrypted SQLCipher v3 MBTiles package in read-only mode,
/// configures PRAGMA settings, maintains a precompiled SQLite statement for high-throughput tile requests,
/// and returns decrypted tile bytes directly into RAM without temporary disk writes.
actor SQLCipherMBTilesReader: SQLCipherMBTilesReaderProtocol {

  private let fileURL: URL
  private var db: OpaquePointer?
  private var statement: OpaquePointer?

  // MARK: - Initializer

  /// Initializes the SQLCipher reader, decrypts the database in memory, and prepares the tile query statement.
  /// - Parameters:
  ///   - fileURL: Local `.mbtiles` file path.
  ///   - encryptionKey: Hex or string key derived from partner secret and customer ID.
  /// - Throws: `CaasError.fileSystemError` or `CaasError.decryptionFailed`.
  init(fileURL: URL, encryptionKey: String) async throws(CaasError) {
    let (openedDB, preparedStmt) = try Self.openAndPrepare(fileURL: fileURL, encryptionKey: encryptionKey)
    self.fileURL = fileURL
    self.db = openedDB
    self.statement = preparedStmt
    Logger.caas.info("SQLCipherMBTilesReader initialized and verified for \(fileURL.lastPathComponent, privacy: .public)")
  }

  deinit {
    if let statement {
      sqlite3_finalize(statement)
    }
    if let db {
      sqlite3_close_v2(db)
    }
  }

  nonisolated private static func openAndPrepare(
    fileURL: URL,
    encryptionKey: String
  ) throws(CaasError) -> (db: OpaquePointer, statement: OpaquePointer) {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw CaasError.fileSystemError(underlying: "MBTiles file does not exist at \(fileURL.path)")
    }

    let keyData = Data(encryptionKey.utf8)

    // 1. Try opening with SQLCipher 4 (default)
    if let result = tryOpen(fileURL: fileURL, keyData: keyData, v3Compatibility: false) {
      return result
    }

    // 2. Fallback: Try opening with SQLCipher 3 legacy compatibility
    if let result = tryOpen(fileURL: fileURL, keyData: keyData, v3Compatibility: true) {
      return result
    }

    throw CaasError.decryptionFailed(reason: "Invalid encryption key or corrupt MBTiles database.")
  }

  nonisolated private static func tryOpen(
    fileURL: URL,
    keyData: Data,
    v3Compatibility: Bool
  ) -> (db: OpaquePointer, statement: OpaquePointer)? {
    var localDB: OpaquePointer?
    guard sqlite3_open_v2(fileURL.path, &localDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let localDB else {
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

  // MARK: - Tile Retrieval

  func tile(z: Int, x: Int, y: Int) -> Data? {
    guard let statement else { return nil }

    // Convert XYZ row (top-left origin) to TMS row (bottom-left origin)
    let tmsY = (1 << z) - 1 - y

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

    // Reset prepared statement and clear parameter bindings for reuse
    sqlite3_reset(statement)
    sqlite3_clear_bindings(statement)

    return tileData
  }

  // MARK: - Close

  func close() {
    if let statement {
      sqlite3_finalize(statement)
      self.statement = nil
    }
    if let db {
      sqlite3_close_v2(db)
      self.db = nil
    }
    Logger.caas.info("SQLCipherMBTilesReader closed.")
  }
}
