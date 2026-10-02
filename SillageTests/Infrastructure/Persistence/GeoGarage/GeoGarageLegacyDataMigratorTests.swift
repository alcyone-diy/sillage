//
//  GeoGarageLegacyDataMigratorTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import GRDB
@testable import Sillage

@MainActor
final class GeoGarageLegacyDataMigratorTests: XCTestCase {

  private var tempDirectory: URL!
  private var dbManager: DatabaseManager!

  override func setUp() async throws {
    try await super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("LegacyETLTests_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbManager = try DatabaseManager.inMemory()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    dbManager = nil
    try await super.tearDown()
  }

  // MARK: - Test Cases

  func testNominalMigration_insertsRecordsAndRenamesFileToMigrated() async throws {
    let jsonURL = tempDirectory.appendingPathComponent("geogarage_downloads.json")
    let migratedURL = tempDirectory.appendingPathComponent("geogarage_downloads.json.migrated")

    let id1 = UUID().uuidString
    let id2 = UUID().uuidString
    let id3 = UUID().uuidString

    let legacyJSON = """
    [
      {
        "id": "\(id1)",
        "layerID": "shom",
        "layerName": "SHOM France",
        "downloadDate": "2026-08-01T12:00:00Z",
        "relativePath": "Charts/shom_1.mbtiles",
        "md5": "md5-1",
        "zoomMax": 12,
        "boundsWKT": "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
        "customName": "Bretagne",
        "customFileSizeBytes": 1048576
      },
      {
        "id": "\(id2)",
        "layerID": "noaa",
        "layerName": "NOAA USA",
        "downloadDate": "2026-08-02T15:30:00Z",
        "relativePath": "Charts/noaa_1.mbtiles",
        "md5": "md5-2",
        "zoomMax": 14,
        "boundsWKT": "POLYGON((-70 40, -65 40, -65 45, -70 45, -70 40))"
      },
      {
        "id": "\(id3)",
        "layerID": "ukho",
        "layerName": "UKHO UK",
        "downloadDate": "2026-08-03T09:00:00Z",
        "relativePath": "Charts/ukho_1.mbtiles",
        "md5": "md5-3",
        "zoomMax": 13,
        "boundsWKT": "POLYGON((-4 50, 1 50, 1 55, -4 55, -4 50))",
        "fileSizeBytes": 2097152
      }
    ]
    """

    try legacyJSON.data(using: .utf8)?.write(to: jsonURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))

    let migrator = GeoGarageLegacyDataMigrator(databaseManager: dbManager, sourceFileURL: jsonURL)
    try await migrator.migrateIfNeeded()

    // 1. Verify file status
    XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path), "Original JSON file should be moved.")
    XCTAssertTrue(FileManager.default.fileExists(atPath: migratedURL.path), "Migrated file should exist.")

    // 2. Verify DB contents
    try await dbManager.reader.read { db in
      let count = try GeoGarageDownloadRecord.fetchCount(db)
      XCTAssertEqual(count, 3)

      let record1 = try GeoGarageDownloadRecord.fetchOne(db, key: id1)
      XCTAssertNotNil(record1)
      XCTAssertEqual(record1?.layer_id, "shom")
      XCTAssertEqual(record1?.layer_name, "SHOM France")
      XCTAssertEqual(record1?.custom_name, "Bretagne")
      XCTAssertEqual(record1?.file_size_bytes, 1048576)

      let record2 = try GeoGarageDownloadRecord.fetchOne(db, key: id2)
      XCTAssertNotNil(record2)
      XCTAssertEqual(record2?.layer_id, "noaa")
      XCTAssertNil(record2?.custom_name)
      XCTAssertNil(record2?.file_size_bytes)

      let record3 = try GeoGarageDownloadRecord.fetchOne(db, key: id3)
      XCTAssertNotNil(record3)
      XCTAssertEqual(record3?.layer_id, "ukho")
      XCTAssertEqual(record3?.file_size_bytes, 2097152)
    }
  }

  func testMigrationIdempotence_doesNotDuplicateRecords() async throws {
    let jsonURL = tempDirectory.appendingPathComponent("geogarage_downloads.json")
    let id = UUID().uuidString

    let legacyJSON = """
    [
      {
        "id": "\(id)",
        "layerID": "shom",
        "layerName": "SHOM France",
        "downloadDate": "2026-08-01T12:00:00Z",
        "relativePath": "Charts/shom_1.mbtiles",
        "md5": "md5-1",
        "zoomMax": 12,
        "boundsWKT": "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))"
      }
    ]
    """

    try legacyJSON.data(using: .utf8)?.write(to: jsonURL)

    let migrator1 = GeoGarageLegacyDataMigrator(databaseManager: dbManager, sourceFileURL: jsonURL)
    try await migrator1.migrateIfNeeded()

    // Recreate the source file with same ID to simulate a re-run
    try legacyJSON.data(using: .utf8)?.write(to: jsonURL)

    let migrator2 = GeoGarageLegacyDataMigrator(databaseManager: dbManager, sourceFileURL: jsonURL)
    try await migrator2.migrateIfNeeded()

    try await dbManager.reader.read { db in
      let count = try GeoGarageDownloadRecord.fetchCount(db)
      XCTAssertEqual(count, 1, "Idempotent insertion must not duplicate records.")
    }
  }

  func testMissingFile_returnsSilentlyWithoutError() async throws {
    let nonExistentURL = tempDirectory.appendingPathComponent("non_existent.json")

    let migrator = GeoGarageLegacyDataMigrator(databaseManager: dbManager, sourceFileURL: nonExistentURL)
    try await migrator.migrateIfNeeded()

    try await dbManager.reader.read { db in
      let count = try GeoGarageDownloadRecord.fetchCount(db)
      XCTAssertEqual(count, 0)
    }
  }

  func testCorruptFile_archivesAsCorruptAndDoesNotThrow() async throws {
    let jsonURL = tempDirectory.appendingPathComponent("geogarage_downloads.json")
    let corruptURL = tempDirectory.appendingPathComponent("geogarage_downloads.json.corrupt")

    let corruptContent = "{ invalid_json: true, unterminated string... "
    try corruptContent.data(using: .utf8)?.write(to: jsonURL)

    let migrator = GeoGarageLegacyDataMigrator(databaseManager: dbManager, sourceFileURL: jsonURL)
    // Should complete cleanly without throwing
    try await migrator.migrateIfNeeded()

    XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: corruptURL.path))

    try await dbManager.reader.read { db in
      let count = try GeoGarageDownloadRecord.fetchCount(db)
      XCTAssertEqual(count, 0)
    }
  }

  func testMigration_supportsDatesWithFractionalSeconds() async throws {
    let jsonURL = tempDirectory.appendingPathComponent("geogarage_downloads.json")
    let id = UUID().uuidString

    let legacyJSON = """
    [
      {
        "id": "\(id)",
        "layerID": "shom",
        "layerName": "SHOM France",
        "downloadDate": "2026-08-01T12:00:00.123Z",
        "relativePath": "Charts/shom_fractional.mbtiles",
        "md5": "md5-fractional",
        "zoomMax": 12,
        "boundsWKT": "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))"
      }
    ]
    """

    try legacyJSON.data(using: .utf8)?.write(to: jsonURL)

    let migrator = GeoGarageLegacyDataMigrator(databaseManager: dbManager, sourceFileURL: jsonURL)
    try await migrator.migrateIfNeeded()

    try await dbManager.reader.read { db in
      let record = try GeoGarageDownloadRecord.fetchOne(db, key: id)
      XCTAssertNotNil(record, "Must successfully parse date with fractional seconds.")
      XCTAssertEqual(record?.layer_id, "shom")
    }
  }
}
