//
//  GeoGarageLayerRepositoryTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class GeoGarageLayerRepositoryTests: XCTestCase {
  private var dbManager: DatabaseManager?
  private var repository: GeoGarageLayerRepository?

  override func setUp() async throws {
    try await super.setUp()
    let manager = try DatabaseManager.inMemory()
    self.dbManager = manager
    self.repository = GeoGarageLayerRepository(databaseManager: manager)
  }

  override func tearDown() async throws {
    repository = nil
    dbManager = nil
    try await super.tearDown()
  }

  // MARK: - Tests

  func testLoadCachedLayers_emptyWhenDatabaseEmpty() async {
    guard let repository else {
      XCTFail("Repository should not be nil")
      return
    }
    let loaded = await repository.loadCachedLayers()
    XCTAssertTrue(loaded.isEmpty, "Repository should return an empty array when database is empty.")
    XCTAssertTrue(repository.layers.isEmpty)
  }

  func testSaveAndLoadCachedLayers() async {
    guard let repository, let dbManager else {
      XCTFail("Repository and dbManager should not be nil")
      return
    }

    let layers = [
      GeoGarageLayer(layer: "shom", brandName: "SHOM", versionDate: "2026-01-01", validUntil: "2027-01-01"),
      GeoGarageLayer(layer: "noaa", brandName: "NOAA", versionDate: "2026-01-01", validUntil: "2027-01-01")
    ]

    await repository.saveLayers(layers)
    XCTAssertEqual(repository.layers.count, 2)

    // Create a new repository instance sharing the same in-memory database
    let newRepo = GeoGarageLayerRepository(databaseManager: dbManager)
    let loaded = await newRepo.loadCachedLayers()

    XCTAssertEqual(loaded.count, 2)
    // Ordered by brand_name ASC: "NOAA" before "SHOM"
    XCTAssertEqual(loaded.first?.layer, "noaa")
    XCTAssertEqual(loaded.first?.brandName, "NOAA")
    XCTAssertEqual(loaded.last?.layer, "shom")
    XCTAssertEqual(loaded.last?.brandName, "SHOM")
  }

  func testSaveLayers_replacesPreviousLayers() async {
    guard let repository else {
      XCTFail("Repository should not be nil")
      return
    }

    let initialLayers = [
      GeoGarageLayer(layer: "shom", brandName: "SHOM", versionDate: "2026-01-01", validUntil: "2027-01-01")
    ]
    await repository.saveLayers(initialLayers)
    XCTAssertEqual(repository.layers.count, 1)

    let updatedLayers = [
      GeoGarageLayer(layer: "ukho", brandName: "UKHO", versionDate: "2026-06-01", validUntil: "2027-06-01"),
      GeoGarageLayer(layer: "bsh", brandName: "BSH", versionDate: "2026-06-01", validUntil: "2027-06-01")
    ]
    await repository.saveLayers(updatedLayers)

    let loaded = await repository.loadCachedLayers()
    XCTAssertEqual(loaded.count, 2)
    let layerNames = Set(loaded.map(\.layer))
    XCTAssertTrue(layerNames.contains("ukho"))
    XCTAssertTrue(layerNames.contains("bsh"))
    XCTAssertFalse(layerNames.contains("shom"))
  }

  func testClearCache_removesDatabaseRecordsAndResetsState() async {
    guard let repository, let dbManager else {
      XCTFail("Repository and dbManager should not be nil")
      return
    }

    let layers = [
      GeoGarageLayer(layer: "shom", brandName: "SHOM", versionDate: "2026-01-01", validUntil: "2027-01-01")
    ]
    await repository.saveLayers(layers)
    XCTAssertEqual(repository.layers.count, 1)

    await repository.clearCache()
    XCTAssertTrue(repository.layers.isEmpty)

    // Verify database table is completely cleared
    let freshRepo = GeoGarageLayerRepository(databaseManager: dbManager)
    let loaded = await freshRepo.loadCachedLayers()
    XCTAssertTrue(loaded.isEmpty)
  }

  func testLegacyCacheMigration_importsJSONAndDeletesFile() async throws {
    guard let dbManager else {
      XCTFail("DatabaseManager should not be nil")
      return
    }

    let tempDir = FileManager.default.temporaryDirectory
    let legacyURL = tempDir.appendingPathComponent("legacy_layers_\(UUID().uuidString).json")

    let legacyLayers = [
      GeoGarageLayer(layer: "linz", brandName: "LINZ", versionDate: "2026-02-01", validUntil: "2027-02-01")
    ]
    let data = try JSONEncoder().encode(legacyLayers)
    try data.write(to: legacyURL)

    defer {
      if FileManager.default.fileExists(atPath: legacyURL.path) {
        try? FileManager.default.removeItem(at: legacyURL)
      }
    }

    XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))

    let repo = GeoGarageLayerRepository(databaseManager: dbManager, legacyCacheFileURL: legacyURL)
    let loaded = await repo.loadCachedLayers()

    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(loaded.first?.layer, "linz")
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path), "Legacy JSON file should be removed after migration.")
  }

  func testClearCache_removesLegacyFileIfPresent() async throws {
    guard let dbManager else {
      XCTFail("DatabaseManager should not be nil")
      return
    }

    let tempDir = FileManager.default.temporaryDirectory
    let legacyURL = tempDir.appendingPathComponent("legacy_layers_\(UUID().uuidString).json")

    let dummyData = Data("[]".utf8)
    try dummyData.write(to: legacyURL)

    defer {
      if FileManager.default.fileExists(atPath: legacyURL.path) {
        try? FileManager.default.removeItem(at: legacyURL)
      }
    }

    XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))

    let repo = GeoGarageLayerRepository(databaseManager: dbManager, legacyCacheFileURL: legacyURL)
    await repo.clearCache()

    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path), "Legacy file should be deleted on clearCache.")
  }
}
