//
//  GeoGarageOfflineTileProviderTests.swift
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
final class GeoGarageOfflineTileProviderTests: XCTestCase {

  private var tempDirURL: URL?
  private var testSubdirName: String = ""

  override func setUp() {
    super.setUp()
    let uniqueID = UUID().uuidString
    testSubdirName = "TestCharts_\(uniqueID)"
    guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let dir = docDir.appendingPathComponent(testSubdirName, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    tempDirURL = dir
  }

  override func tearDown() {
    if let tempDirURL {
      try? FileManager.default.removeItem(at: tempDirURL)
    }
    super.tearDown()
  }

  // MARK: - Test Helpers

  private func createEncryptedMBTiles(
    fileName: String,
    encryptionKey: String,
    tiles: [(z: Int, x: Int, y: Int, data: Data)]
  ) throws -> URL {
    guard let tempDirURL else {
      throw CaasError.fileSystemError(underlying: "Missing tempDirURL")
    }

    let fileURL = tempDirURL.appendingPathComponent(fileName)
    var db: OpaquePointer?
    guard sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
      throw CaasError.fileSystemError(underlying: "Failed to create sqlite db")
    }

    let keyData = Data(encryptionKey.utf8)
    let keyResult = keyData.withUnsafeBytes { rawBuffer in
      sqlite3_key(db, rawBuffer.baseAddress, Int32(keyData.count))
    }
    guard keyResult == SQLITE_OK else {
      sqlite3_close_v2(db)
      throw CaasError.decryptionFailed(reason: "sqlite3_key failed")
    }

    let pragmaCommands = "PRAGMA cipher_compatibility = 3;"
    var pragmaErrMsg: UnsafeMutablePointer<CChar>?
    let pragmaCode = sqlite3_exec(db, pragmaCommands, nil, nil, &pragmaErrMsg)
    if pragmaCode != SQLITE_OK {
      let msg = pragmaErrMsg != nil ? String(cString: pragmaErrMsg!) : "Unknown"
      sqlite3_free(pragmaErrMsg)
      sqlite3_close_v2(db)
      throw CaasError.decryptionFailed(reason: "PRAGMA failed: \(msg)")
    }

    let createTableSQL = """
    CREATE TABLE metadata (name text, value text);
    CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
    """
    guard sqlite3_exec(db, createTableSQL, nil, nil, nil) == SQLITE_OK else {
      sqlite3_close_v2(db)
      throw CaasError.fileSystemError(underlying: "Create tables failed")
    }

    let insertSQL = "INSERT INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?);"
    for tile in tiles {
      var insertStmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK, let insertStmt else {
        sqlite3_close_v2(db)
        throw CaasError.fileSystemError(underlying: "Prepare insert failed")
      }

      let tmsY = (1 << tile.z) - 1 - tile.y
      sqlite3_bind_int(insertStmt, 1, Int32(tile.z))
      sqlite3_bind_int(insertStmt, 2, Int32(tile.x))
      sqlite3_bind_int(insertStmt, 3, Int32(tmsY))
      tile.data.withUnsafeBytes { rawBuffer in
        sqlite3_bind_blob(insertStmt, 4, rawBuffer.baseAddress, Int32(tile.data.count), nil)
        _ = sqlite3_step(insertStmt)
      }
      sqlite3_finalize(insertStmt)
    }

    sqlite3_close_v2(db)
    return fileURL
  }

  // MARK: - Unit Tests

  func testTile_returnsTileFromMatchingLayer() async throws {
    let secret = "partnerSecret123"
    let customerID = "cus_abc999"
    let key = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: secret, customerID: customerID)

    guard let tileData = "SHOM_TILE_SAMPLE_DATA".data(using: .utf8) else {
      XCTFail("Failed to encode tileData")
      return
    }

    let fileName = "shom_brest.mbtiles"
    _ = try createEncryptedMBTiles(
      fileName: fileName,
      encryptionKey: key,
      tiles: [(z: 12, x: 2048, y: 1360, data: tileData)]
    )

    let downloadID = UUID()
    let download = OfflineChartDownload(
      id: downloadID,
      layerID: "shom",
      layerName: "SHOM France",
      downloadDate: Date(),
      relativePath: "\(testSubdirName)/\(fileName)",
      md5: "mock_md5",
      zoomMax: 14,
      boundsWKT: "POLYGON((-5 48, -4 48, -4 49, -5 49, -5 48))"
    )

    let provider = GeoGarageOfflineTileProvider()
    await provider.reloadDownloads([download], sharedSecret: secret, customerID: customerID)

    let result = await provider.tile(layerID: "shom", z: 12, x: 2048, y: 1360)
    XCTAssertEqual(result, tileData)

    let missingResult = await provider.tile(layerID: "shom", z: 12, x: 9999, y: 9999)
    XCTAssertNil(missingResult)

    let wrongLayerResult = await provider.tile(layerID: "ukho", z: 12, x: 2048, y: 1360)
    XCTAssertNil(wrongLayerResult)

    await provider.close()
  }

  func testTile_returnsNilForInvalidParameters() async {
    let provider = GeoGarageOfflineTileProvider()

    let emptyLayer = await provider.tile(layerID: "", z: 10, x: 10, y: 10)
    XCTAssertNil(emptyLayer)

    let negativeZ = await provider.tile(layerID: "shom", z: -1, x: 10, y: 10)
    XCTAssertNil(negativeZ)

    let negativeX = await provider.tile(layerID: "shom", z: 10, x: -1, y: 10)
    XCTAssertNil(negativeX)

    let negativeY = await provider.tile(layerID: "shom", z: 10, x: 10, y: -1)
    XCTAssertNil(negativeY)
  }

  func testConcurrentTileFetching() async throws {
    let secret = "partnerSecret123"
    let customerID = "cus_abc999"
    let key = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: secret, customerID: customerID)

    var tiles: [(z: Int, x: Int, y: Int, data: Data)] = []
    for i in 0..<10 {
      let data = "TILE_PAYLOAD_\(i)".data(using: .utf8) ?? Data()
      tiles.append((z: 10, x: 100 + i, y: 200 + i, data: data))
    }

    let fileName = "concurrent_test.mbtiles"
    _ = try createEncryptedMBTiles(
      fileName: fileName,
      encryptionKey: key,
      tiles: tiles
    )

    let download = OfflineChartDownload(
      id: UUID(),
      layerID: "shom",
      layerName: "SHOM France",
      downloadDate: Date(),
      relativePath: "\(testSubdirName)/\(fileName)",
      md5: "mock_md5",
      zoomMax: 14,
      boundsWKT: "POLYGON((-5 48, -4 48, -4 49, -5 49, -5 48))"
    )

    let provider = GeoGarageOfflineTileProvider()
    await provider.reloadDownloads([download], sharedSecret: secret, customerID: customerID)

    // Execute 100 simultaneous concurrent tile requests
    let totalRequests = 100
    let successfulFetches = await withTaskGroup(of: (Int, Data?).self, returning: Int.self) { group in
      for requestIndex in 0..<totalRequests {
        let tileIndex = requestIndex % tiles.count
        let targetTile = tiles[tileIndex]

        group.addTask {
          let data = await provider.tile(layerID: "shom", z: targetTile.z, x: targetTile.x, y: targetTile.y)
          return (tileIndex, data)
        }
      }

      var successCount = 0
      for await (tileIndex, data) in group {
        let expectedData = tiles[tileIndex].data
        if data == expectedData {
          successCount += 1
        }
      }
      return successCount
    }

    XCTAssertEqual(successfulFetches, totalRequests, "All 100 concurrent tile queries must succeed without lock or contention errors")

    await provider.close()
  }

  func testReloadDownloads_replacesAndClosesReaders() async throws {
    let secret = "partnerSecret123"
    let customerID = "cus_abc999"
    let key = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: secret, customerID: customerID)

    let tileData1 = "DATA_1".data(using: .utf8) ?? Data()
    let tileData2 = "DATA_2".data(using: .utf8) ?? Data()

    let fileName1 = "db1.mbtiles"
    let fileName2 = "db2.mbtiles"

    _ = try createEncryptedMBTiles(
      fileName: fileName1,
      encryptionKey: key,
      tiles: [(z: 8, x: 10, y: 10, data: tileData1)]
    )
    _ = try createEncryptedMBTiles(
      fileName: fileName2,
      encryptionKey: key,
      tiles: [(z: 8, x: 20, y: 20, data: tileData2)]
    )

    let download1 = OfflineChartDownload(
      id: UUID(),
      layerID: "shom",
      layerName: "Package 1",
      downloadDate: Date(),
      relativePath: "\(testSubdirName)/\(fileName1)",
      md5: "md5_1",
      zoomMax: 10,
      boundsWKT: "POLYGON((-5 48, -4 48, -4 49, -5 49, -5 48))"
    )
    let download2 = OfflineChartDownload(
      id: UUID(),
      layerID: "shom",
      layerName: "Package 2",
      downloadDate: Date(),
      relativePath: "\(testSubdirName)/\(fileName2)",
      md5: "md5_2",
      zoomMax: 10,
      boundsWKT: "POLYGON((-5 48, -4 48, -4 49, -5 49, -5 48))"
    )

    let provider = GeoGarageOfflineTileProvider()

    // 1. Initial reload with package 1
    await provider.reloadDownloads([download1], sharedSecret: secret, customerID: customerID)
    let res1 = await provider.tile(layerID: "shom", z: 8, x: 10, y: 10)
    XCTAssertEqual(res1, tileData1)
    let res2Before = await provider.tile(layerID: "shom", z: 8, x: 20, y: 20)
    XCTAssertNil(res2Before)

    // 2. Reload replacing package 1 with package 2
    await provider.reloadDownloads([download2], sharedSecret: secret, customerID: customerID)
    let res1After = await provider.tile(layerID: "shom", z: 8, x: 10, y: 10)
    XCTAssertNil(res1After, "Old package 1 should no longer be queried")
    let res2After = await provider.tile(layerID: "shom", z: 8, x: 20, y: 20)
    XCTAssertEqual(res2After, tileData2)

    await provider.close()
  }
}
