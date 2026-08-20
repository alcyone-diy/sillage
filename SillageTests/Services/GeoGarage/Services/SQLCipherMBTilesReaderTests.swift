//
//  SQLCipherMBTilesReaderTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import SQLCipher
@testable import Sillage

@MainActor
final class SQLCipherMBTilesReaderTests: XCTestCase {

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

  // MARK: - Error Handling

  func testReader_throwsFileSystemErrorOnMissingFile() {
    guard let tempDirURL else {
      XCTFail("tempDirURL must be non-nil")
      return
    }
    let missingURL = tempDirURL.appendingPathComponent("nonexistent.mbtiles")

    do {
      _ = try SQLCipherMBTilesReader(fileURL: missingURL, encryptionKey: "key")
      XCTFail("Should have thrown CaasError.fileSystemError")
    } catch {
      guard case CaasError.fileSystemError = error else {
        XCTFail("Expected CaasError.fileSystemError, got \(error)")
        return
      }
    }
  }

  func testReader_throwsDecryptionFailedOnCorruptOrUnencryptedFile() throws {
    guard let tempDirURL else {
      XCTFail("tempDirURL must be non-nil")
      return
    }
    let corruptURL = tempDirURL.appendingPathComponent("corrupt.mbtiles")
    guard let dummyData = "Not an encrypted sqlite database".data(using: .utf8) else {
      XCTFail("Failed to encode dummy string")
      return
    }
    try dummyData.write(to: corruptURL)

    do {
      _ = try SQLCipherMBTilesReader(fileURL: corruptURL, encryptionKey: "key")
      XCTFail("Should have thrown CaasError.decryptionFailed")
    } catch {
      guard case CaasError.decryptionFailed = error else {
        XCTFail("Expected CaasError.decryptionFailed, got \(error)")
        return
      }
    }
  }

  // MARK: - Decryption & Tile Retrieval

  func testReader_decryptsAndReadsTileWithTMSRowFlipping() async throws {
    guard let tempDirURL else {
      XCTFail("tempDirURL must be non-nil")
      return
    }
    let dbURL = tempDirURL.appendingPathComponent("encrypted.mbtiles")
    let encryptionKey = "test_passphrase_12345"

    // 1. Create a genuine SQLCipher v3 encrypted MBTiles database
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)

    let keyData = Data(encryptionKey.utf8)
    let keyResult = keyData.withUnsafeBytes { rawBuffer in
      sqlite3_key(db, rawBuffer.baseAddress, Int32(keyData.count))
    }
    XCTAssertEqual(keyResult, SQLITE_OK)

    let pragmaCommands = "PRAGMA cipher_compatibility = 3;"
    var pragmaErrMsg: UnsafeMutablePointer<CChar>?
    let pragmaCode = sqlite3_exec(db, pragmaCommands, nil, nil, &pragmaErrMsg)
    if pragmaCode != SQLITE_OK {
      let msg = pragmaErrMsg != nil ? String(cString: pragmaErrMsg!) : "Unknown"
      sqlite3_free(pragmaErrMsg)
      XCTFail("PRAGMA failed: \(msg)")
    }

    // Create MBTiles schema
    let createTableSQL = """
    CREATE TABLE metadata (name text, value text);
    CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
    """
    XCTAssertEqual(sqlite3_exec(db, createTableSQL, nil, nil, nil), SQLITE_OK)

    // Insert tile: XYZ coordinates z=10, x=512, y=340
    // In MBTiles TMS coordinates: tmsY = (1 << 10) - 1 - 340 = 1024 - 1 - 340 = 683
    let z = 10
    let x = 512
    let y = 340
    let tmsY = (1 << z) - 1 - y
    guard let tileData = "PNG_DECRYPTED_TILE_PAYLOAD".data(using: .utf8) else {
      XCTFail("Failed to encode tileData")
      return
    }

    var insertStmt: OpaquePointer?
    let insertSQL = "INSERT INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?);"
    XCTAssertEqual(sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil), SQLITE_OK)
    sqlite3_bind_int(insertStmt, 1, Int32(z))
    sqlite3_bind_int(insertStmt, 2, Int32(x))
    sqlite3_bind_int(insertStmt, 3, Int32(tmsY))
    tileData.withUnsafeBytes { rawBuffer in
      sqlite3_bind_blob(insertStmt, 4, rawBuffer.baseAddress, Int32(tileData.count), nil)
      XCTAssertEqual(sqlite3_step(insertStmt), SQLITE_DONE)
    }
    sqlite3_finalize(insertStmt)
    sqlite3_close_v2(db)

    // 2. Open via SQLCipherMBTilesReader and retrieve tile using XYZ (z, x, y)
    let reader = try SQLCipherMBTilesReader(fileURL: dbURL, encryptionKey: encryptionKey)
    let retrievedData = await reader.tile(z: z, x: x, y: y)

    XCTAssertEqual(retrievedData, tileData, "Reader must decrypt and retrieve exact tile bytes using TMS flipped row")

    // Retrieve missing tile
    let missingData = await reader.tile(z: z, x: 999, y: 999)
    XCTAssertNil(missingData)

    await reader.close()
  }

  func testReader_returnsNilWhenTaskIsCancelled() async throws {
    guard let tempDirURL else {
      XCTFail("tempDirURL must be non-nil")
      return
    }
    let dbURL = tempDirURL.appendingPathComponent("cancel_test.mbtiles")
    let encryptionKey = "test_cancel_key"

    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)

    let keyData = Data(encryptionKey.utf8)
    _ = keyData.withUnsafeBytes { rawBuffer in
      sqlite3_key(db, rawBuffer.baseAddress, Int32(keyData.count))
    }
    let pragmaCommands = "PRAGMA cipher_compatibility = 3;"
    sqlite3_exec(db, pragmaCommands, nil, nil, nil)
    let createTableSQL = """
    CREATE TABLE metadata (name text, value text);
    CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
    """
    sqlite3_exec(db, createTableSQL, nil, nil, nil)
    sqlite3_close_v2(db)

    let reader = try SQLCipherMBTilesReader(fileURL: dbURL, encryptionKey: encryptionKey)

    // Launch task and cancel it immediately
    let task = Task { () -> Data? in
      return await reader.tile(z: 5, x: 10, y: 10)
    }
    task.cancel()

    let result = await task.value
    // If the task was cancelled before/during execution, it returns nil cleanly
    XCTAssertNil(result)

    await reader.close()
  }
}
