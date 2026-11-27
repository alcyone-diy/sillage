//
//  MBTilesDownloadWorkerTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
import GRDB
import os
@testable import Sillage

/// Swift 6 Actor mock implementation of `TileFetchPipeline` ensuring actor-isolated
/// state tracking without manual locking primitives (`NSLock` / `DispatchQueue`).
actor MockTileFetchPipeline: TileFetchPipeline {
  nonisolated let format: String = "png"
  private(set) var fetchedCoordinates: [TileCoordinate] = []

  init() {}

  func fetchTileData(zoom: Int, x: Int, y: Int) async throws -> Data? {
    let coord = TileCoordinate(zoom: zoom, x: x, y: y)
    fetchedCoordinates.append(coord)
    return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, UInt8(zoom & 0xFF), UInt8(x & 0xFF), UInt8(y & 0xFF)])
  }

  var fetchCount: Int {
    fetchedCoordinates.count
  }
}

final class MBTilesDownloadWorkerTests: XCTestCase {

  private var tempDirectory: URL!

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MBTilesWorkerTests_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    super.tearDown()
  }

  // MARK: - Worker SQLite & Resumability Tests

  func testWorkerCreatesMBTilesAndWritesMetadataAndTiles() async throws {
    let worker = MBTilesDownloadWorker()
    let pipeline = MockTileFetchPipeline()
    let destinationURL = tempDirectory.appendingPathComponent("test_chart.mbtiles")

    // Bounding box around La Rochelle harbor
    let bounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 46.14, longitude: -1.18),
      northEast: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.16)
    )

    let progressTracker = OSAllocatedUnfairLock<MBTilesDownloadProgress?>(initialState: nil)
    try await worker.executeDownload(
      bounds: bounds,
      minZoom: 10,
      maxZoom: 11,
      destinationURL: destinationURL,
      regionName: "La Rochelle Test",
      pipeline: pipeline
    ) { progress in
      progressTracker.withLock { $0 = progress }
    }

    let lastProgress = progressTracker.withLock { $0 }
    XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    XCTAssertNotNil(lastProgress)
    XCTAssertEqual(lastProgress?.percentage, 1.0)
    let fetchCount = await pipeline.fetchCount
    XCTAssertGreaterThan(fetchCount, 0)

    // Inspect generated SQLite via GRDB
    let dbQueue = try DatabaseQueue(path: destinationURL.path)
    try await dbQueue.read { db in
      // Verify metadata table
      let name = try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE name = 'name'")
      XCTAssertEqual(name, "La Rochelle Test")

      let format = try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE name = 'format'")
      XCTAssertEqual(format, "png")

      let minZoom = try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE name = 'minzoom'")
      XCTAssertEqual(minZoom, "10")

      let maxZoom = try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE name = 'maxzoom'")
      XCTAssertEqual(maxZoom, "11")

      // Verify tiles table
      let tileCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tiles")
      XCTAssertEqual(tileCount, fetchCount)
    }
  }

  func testWorkerResumabilitySkipsAlreadyDownloadedTiles() async throws {
    let worker = MBTilesDownloadWorker()
    let pipeline = MockTileFetchPipeline()
    let destinationURL = tempDirectory.appendingPathComponent("resumable_chart.mbtiles")

    let bounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 46.14, longitude: -1.18),
      northEast: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.16)
    )

    // First download run
    try await worker.executeDownload(
      bounds: bounds,
      minZoom: 10,
      maxZoom: 11,
      destinationURL: destinationURL,
      regionName: "Resumable Test",
      pipeline: pipeline
    )
    let firstRunFetchCount = await pipeline.fetchCount
    XCTAssertGreaterThan(firstRunFetchCount, 0)

    // Second download run on the exact same file
    let secondPipeline = MockTileFetchPipeline()
    try await worker.executeDownload(
      bounds: bounds,
      minZoom: 10,
      maxZoom: 11,
      destinationURL: destinationURL,
      regionName: "Resumable Test",
      pipeline: secondPipeline
    )

    // Crucial Resumability Check: 0 fetches must be performed since all tiles exist in SQLite!
    let secondRunFetchCount = await secondPipeline.fetchCount
    XCTAssertEqual(secondRunFetchCount, 0)
  }
}
