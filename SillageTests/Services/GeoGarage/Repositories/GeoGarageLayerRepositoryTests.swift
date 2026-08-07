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
  private var tempFileURL: URL!
  private var repository: GeoGarageLayerRepository!

  override func setUp() {
    super.setUp()
    let tempDir = FileManager.default.temporaryDirectory
    tempFileURL = tempDir.appendingPathComponent("test_geogarage_layers_\(UUID().uuidString).json")
    repository = GeoGarageLayerRepository(cacheFileURL: tempFileURL)
  }

  override func tearDown() {
    if FileManager.default.fileExists(atPath: tempFileURL.path) {
      try? FileManager.default.removeItem(at: tempFileURL)
    }
    repository = nil
    super.tearDown()
  }

  func testSaveAndLoadCachedLayers() async {
    let layers = [
      GeoGarageLayer(layer: "shom", brand_name: "SHOM", version_date: "2026-01-01", valid_until: "2027-01-01"),
      GeoGarageLayer(layer: "noaa", brand_name: "NOAA", version_date: "2026-01-01", valid_until: "2027-01-01")
    ]

    await repository.saveLayers(layers)
    XCTAssertEqual(repository.layers.count, 2)

    // Create a new repository instance pointing to the same file
    let newRepo = GeoGarageLayerRepository(cacheFileURL: tempFileURL)
    let loaded = await newRepo.loadCachedLayers()

    XCTAssertEqual(loaded.count, 2)
    XCTAssertEqual(loaded[0].layer, "shom")
    XCTAssertEqual(loaded[1].brand_name, "NOAA")
  }

  func testClearCacheRemovesFileAndResetsState() async {
    let layers = [
      GeoGarageLayer(layer: "shom", brand_name: "SHOM", version_date: "2026-01-01", valid_until: "2027-01-01")
    ]

    await repository.saveLayers(layers)
    XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))

    await repository.clearCache()
    XCTAssertTrue(repository.layers.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
  }
}
