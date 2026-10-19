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

  private func createTestEncryptedDB(fileName: String, key: String, v3Compatibility: Bool = true) throws -> URL {
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

    if v3Compatibility {
      let pragmaCommands = "PRAGMA cipher_compatibility = 3;"
      sqlite3_exec(db, pragmaCommands, nil, nil, nil)
    }

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
      requiresV3Compatibility: true,
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
      requiresV3Compatibility: true,
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

  func testPool_opensSQLCipher3Archive() async throws {
    let key = "mock_secret_v3_passphrase"
    let dbURL = try createTestEncryptedDB(fileName: "pool_v3_test.mbtiles", key: key, v3Compatibility: true)

    let pool = try SQLiteConnectionPool(
      fileURL: dbURL,
      encryptionKey: key,
      requiresV3Compatibility: true,
      maxConnections: 2,
      prewarmCount: 1
    )

    let handle = try await pool.borrow()
    await pool.returnHandle(handle)
    await pool.close()
  }

  func testPool_opensSQLCipher4Archive() async throws {
    let key = "mock_secret_v4_passphrase"
    let dbURL = try createTestEncryptedDB(fileName: "pool_v4_test.mbtiles", key: key, v3Compatibility: false)

    let pool = try SQLiteConnectionPool(
      fileURL: dbURL,
      encryptionKey: key,
      requiresV3Compatibility: false,
      maxConnections: 2,
      prewarmCount: 1
    )

    let handle = try await pool.borrow()
    await pool.returnHandle(handle)
    await pool.close()
  }

  func testPool_throwsDecryptionFailedOnInvalidKey() async throws {
    let actualKey = "real_key_12345"
    let wrongKey = "wrong_attacker_key"
    let dbURL = try createTestEncryptedDB(fileName: "pool_invalid_key_test.mbtiles", key: actualKey, v3Compatibility: true)

    do {
      _ = try SQLiteConnectionPool(
        fileURL: dbURL,
        encryptionKey: wrongKey,
        requiresV3Compatibility: true,
        maxConnections: 1,
        prewarmCount: 1
      )
      XCTFail("Must throw CaasError.decryptionFailed when key is invalid")
    } catch {
      guard case CaasError.decryptionFailed = error else {
        XCTFail("Expected CaasError.decryptionFailed, got \(error)")
        return
      }
    }
  }

  func testPool_adaptiveFallback_opensV3ArchiveWhenDefaultIsV4() async throws {
    let key = "adaptive_v3_key"
    let dbURL = try createTestEncryptedDB(fileName: "pool_adaptive_v3.mbtiles", key: key, v3Compatibility: true)

    // Initializing with default requiresV3Compatibility (false = SQLCipher 4)
    // Adaptive fallback must seamlessly fall back to v3 compatibility
    let pool = try SQLiteConnectionPool(
      fileURL: dbURL,
      encryptionKey: key,
      requiresV3Compatibility: false,
      maxConnections: 2,
      prewarmCount: 1
    )

    let isV3 = pool.effectiveRequiresV3Compatibility
    XCTAssertTrue(isV3, "Pool must adaptively resolve to v3 compatibility when v4 HMAC check fails")

    let handle = try await pool.borrow()
    await pool.returnHandle(handle)
    await pool.close()
  }

  func testPool_adaptiveFallback_opensV4ArchiveWhenV3Requested() async throws {
    let key = "adaptive_v4_key"
    let dbURL = try createTestEncryptedDB(fileName: "pool_adaptive_v4.mbtiles", key: key, v3Compatibility: false)

    // Initializing with explicit requiresV3Compatibility = true on a v4 archive
    // Adaptive fallback must seamlessly fall back to v4
    let pool = try SQLiteConnectionPool(
      fileURL: dbURL,
      encryptionKey: key,
      requiresV3Compatibility: true,
      maxConnections: 2,
      prewarmCount: 1
    )

    let isV3 = pool.effectiveRequiresV3Compatibility
    XCTAssertFalse(isV3, "Pool must adaptively resolve to v4 compatibility when v3 PRAGMA fails")

    let handle = try await pool.borrow()
    await pool.returnHandle(handle)
    await pool.close()
  }
}
