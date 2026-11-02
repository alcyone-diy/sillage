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

  // MARK: - Mathematical Coordinate Tests

  func testTileCoordinateTMSInversion() {
    // Zoom 0: 1 tile (0, 0, 0) -> TMS row = 0
    let coordZ0 = TileCoordinate(zoom: 0, x: 0, y: 0)
    XCTAssertEqual(coordZ0.tmsRow, 0)

    // Zoom 1: y=0 (North) -> TMS row = 1
    let coordZ1North = TileCoordinate(zoom: 1, x: 0, y: 0)
    XCTAssertEqual(coordZ1North.tmsRow, 1)

    // Zoom 1: y=1 (South) -> TMS row = 0
    let coordZ1South = TileCoordinate(zoom: 1, x: 0, y: 1)
    XCTAssertEqual(coordZ1South.tmsRow, 0)

    // Zoom 3: max y = 7. y=0 -> TMS row = 7, y=7 -> TMS row = 0
    let coordZ3Top = TileCoordinate(zoom: 3, x: 4, y: 0)
    let coordZ3Bottom = TileCoordinate(zoom: 3, x: 4, y: 7)
    XCTAssertEqual(coordZ3Top.tmsRow, 7)
    XCTAssertEqual(coordZ3Bottom.tmsRow, 0)
  }

  func testMercatorTileProjectionWithMeasurement() {
    // Equator / Prime Meridian (0, 0) at Zoom 1
    let x = MBTilesCoordinateMath.tileX(longitude: 0, zoom: 1)
    let y = MBTilesCoordinateMath.tileY(latitude: 0, zoom: 1)
    XCTAssertEqual(x, 1)
    XCTAssertEqual(y, 1)

    // La Rochelle (~46.15° N, ~1.15° W) at Zoom 10
    let lrX = MBTilesCoordinateMath.tileX(longitude: -1.15, zoom: 10)
    let lrY = MBTilesCoordinateMath.tileY(latitude: 46.15, zoom: 10)
    XCTAssertNotNil(lrX)
    XCTAssertNotNil(lrY)
    if let lrX, let lrY {
      XCTAssertGreaterThan(lrX, 0)
      XCTAssertGreaterThan(lrY, 0)
      XCTAssertLessThan(lrX, 1024)
      XCTAssertLessThan(lrY, 1024)
    }
  }

  func testNilOverDefaultsForInvalidInputs() {
    // Invalid zoom (< 0 or > 30)
    XCTAssertNil(MBTilesCoordinateMath.tileX(longitude: 0, zoom: -1))
    XCTAssertNil(MBTilesCoordinateMath.tileX(longitude: 0, zoom: 31))
    XCTAssertNil(MBTilesCoordinateMath.tileY(latitude: 0, zoom: -1))

    // Invalid coordinates (NaN, Infinite, out-of-bounds)
    XCTAssertNil(MBTilesCoordinateMath.tileX(longitude: .nan, zoom: 5))
    XCTAssertNil(MBTilesCoordinateMath.tileX(longitude: 195.0, zoom: 5))
    XCTAssertNil(MBTilesCoordinateMath.tileY(latitude: .infinity, zoom: 5))
    XCTAssertNil(MBTilesCoordinateMath.tileY(latitude: 89.0, zoom: 5)) // Beyond Mercator limit ~85.0511°

    // Invalid TMS row / Slippy Y (out-of-bounds index)
    XCTAssertNil(MBTilesCoordinateMath.tmsRow(slippyY: 10, zoom: 1)) // Zoom 1 only has y in 0...1
    XCTAssertNil(MBTilesCoordinateMath.slippyY(tmsRow: -1, zoom: 1))

    let invalidCoord = TileCoordinate(zoom: 1, x: 0, y: 99)
    XCTAssertNil(invalidCoord.tmsRow)
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
