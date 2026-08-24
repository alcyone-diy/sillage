//
//  SQLiteConnectionPoolTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import SQLCipher
@testable import Sillage

@MainActor
final class SQLiteConnectionPoolTests: XCTestCase {

  private var tempDirURL: URL?

  override func setUp() {
    super.setUp()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    tempDirURL = dir
  }

  override func tearDown() {
    if let tempDirURL {
      try? FileManager.default.removeItem(at: tempDirURL)
    }
    super.tearDown()
  }

  private func createTestEncryptedDB(fileName: String, key: String) throws -> URL {
    guard let tempDirURL else {
      throw CaasError.fileSystemError(underlying: "Missing tempDirURL")
    }

    let fileURL = tempDirURL.appendingPathComponent(fileName)
    var db: OpaquePointer?
    guard sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
      throw CaasError.fileSystemError(underlying: "Failed to create sqlite db")
    }

    let keyData = Data(key.utf8)
    let keyResult = keyData.withUnsafeBytes { rawBuffer in
      sqlite3_key(db, rawBuffer.baseAddress, Int32(keyData.count))
    }
    guard keyResult == SQLITE_OK else {
      sqlite3_close_v2(db)
      throw CaasError.decryptionFailed(reason: "sqlite3_key failed")
    }

    let pragmaCommands = "PRAGMA cipher_compatibility = 3;"
    sqlite3_exec(db, pragmaCommands, nil, nil, nil)

    let createTableSQL = """
    CREATE TABLE metadata (name text, value text);
    CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
    """
    guard sqlite3_exec(db, createTableSQL, nil, nil, nil) == SQLITE_OK else {
      sqlite3_close_v2(db)
      throw CaasError.fileSystemError(underlying: "Create tables failed")
    }

    sqlite3_close_v2(db)
    return fileURL
  }

  func testPool_prewarmsAndBorrowsWithinLimit() async throws {
    let key = "pool_test_key"
    let dbURL = try createTestEncryptedDB(fileName: "pool_test.mbtiles", key: key)

    let pool = try SQLiteConnectionPool(
      fileURL: dbURL,
      encryptionKey: key,
      maxConnections: 3,
      prewarmCount: 2
    )

    let handle1 = try await pool.borrow()
    let handle2 = try await pool.borrow()
    let handle3 = try await pool.borrow()

    // Return handles back to pool
    await pool.returnHandle(handle1)
    await pool.returnHandle(handle2)
    await pool.returnHandle(handle3)

    await pool.close()
  }

  func testPool_suspendsAndResumesWaitersInFIFO() async throws {
    let key = "pool_fifo_key"
    let dbURL = try createTestEncryptedDB(fileName: "pool_fifo.mbtiles", key: key)

    let pool = try SQLiteConnectionPool(
      fileURL: dbURL,
      encryptionKey: key,
      maxConnections: 1,
      prewarmCount: 1
    )

    let handle1 = try await pool.borrow()

    // Task that attempts to borrow when pool is full (should suspend)
    let borrowTask = Task { () -> Bool in
      let handle2 = try await pool.borrow()
      await pool.returnHandle(handle2)
      return true
    }

    // Give the task a moment to enter the waiting queue
    try await Task.sleep(nanoseconds: 50_000_000)

    // Returning handle1 should wake up borrowTask
    await pool.returnHandle(handle1)

    let result = try await borrowTask.value
    XCTAssertTrue(result, "Waiter must be resumed once a connection handle is returned")

    await pool.close()
  }
}
