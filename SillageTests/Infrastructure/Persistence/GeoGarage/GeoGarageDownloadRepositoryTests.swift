//
//  GeoGarageDownloadRepositoryTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class GeoGarageDownloadRepositoryTests: XCTestCase {

  private var dbManager: DatabaseManager!
  private var repository: GeoGarageDownloadRepository!

  override func setUp() async throws {
    try await super.setUp()
    dbManager = try DatabaseManager.inMemory()
    repository = GeoGarageDownloadRepository(databaseManager: dbManager)
  }

  override func tearDown() async throws {
    repository = nil
    dbManager = nil
    try await super.tearDown()
  }

  // MARK: - Helpers

  private func makeDownload(
    id: UUID = UUID(),
    layerID: String = "shom",
    layerName: String = "SHOM France",
    downloadDate: Date = Date(),
    fileSize: Measurement<UnitInformationStorage>? = Measurement(value: 1048576, unit: .bytes)
  ) -> OfflineChartDownload {
    OfflineChartDownload(
      id: id,
      layerID: layerID,
      layerName: layerName,
      downloadDate: downloadDate,
      relativePath: "Charts/\(layerID)_test.mbtiles",
      md5: "d41d8cd98f00b204e9800998ecf8427e",
      zoomMax: 14,
      boundsWKT: "POLYGON((-5.0 47.0, 0.0 47.0, 0.0 50.0, -5.0 50.0, -5.0 47.0))",
      fileSize: fileSize
    )
  }

  // MARK: - Load

  func testLoad_emptyWhenDatabaseEmpty() async {
    await repository.load()
    XCTAssertTrue(repository.downloads.isEmpty, "Repository must start empty when database has no records.")
  }

  // MARK: - Save

  func testSave_appendsNewDownload() async throws {
    let download = makeDownload()
    try await repository.save(download)

    XCTAssertEqual(repository.downloads.count, 1)
    XCTAssertEqual(repository.downloads.first?.id, download.id)
  }

  func testSave_isIdempotent_sameID() async throws {
    let download = makeDownload()
    let updatedDownload = OfflineChartDownload(
      id: download.id,
      layerID: download.layerID,
      layerName: "Updated SHOM",
      downloadDate: Date(),
      relativePath: download.relativePath,
      md5: "newmd5",
      zoomMax: 16,
      boundsWKT: download.boundsWKT,
      fileSize: Measurement(value: 2097152, unit: .bytes)
    )

    try await repository.save(download)
    try await repository.save(updatedDownload)

    XCTAssertEqual(repository.downloads.count, 1, "Saving an entry with existing ID must update in-place without duplicating.")
    XCTAssertEqual(repository.downloads.first?.layerName, "Updated SHOM")
    XCTAssertEqual(repository.downloads.first?.md5, "newmd5")
    XCTAssertEqual(repository.downloads.first?.fileSize, Measurement(value: 2097152, unit: .bytes))
  }

  func testSave_multipleDifferentDownloads() async throws {
    let d1 = makeDownload(layerID: "shom")
    let d2 = makeDownload(layerID: "noaa")

    try await repository.save(d1)
    try await repository.save(d2)

    XCTAssertEqual(repository.downloads.count, 2)
  }

  // MARK: - Delete

  func testDelete_removesCorrectEntry() async throws {
    let d1 = makeDownload(layerID: "shom")
    let d2 = makeDownload(layerID: "noaa")

    try await repository.save(d1)
    try await repository.save(d2)
    try await repository.delete(id: d1.id)

    XCTAssertEqual(repository.downloads.count, 1)
    XCTAssertEqual(repository.downloads.first?.layerID, "noaa")
  }

  func testDelete_noOpOnNonexistentID() async throws {
    let download = makeDownload()
    try await repository.save(download)

    try await repository.delete(id: UUID())

    XCTAssertEqual(repository.downloads.count, 1, "Deleting an unknown UUID should not modify existing entries.")
  }

  // MARK: - Persistence (Reload across instances)

  func testPersistence_survivesReloadAcrossInstances() async throws {
    let download = makeDownload()

    // Write via first repository instance
    try await repository.save(download)

    // Read via a fresh repository instance connected to the same database
    let freshRepository = GeoGarageDownloadRepository(databaseManager: dbManager)
    await freshRepository.load()

    XCTAssertEqual(freshRepository.downloads.count, 1)
    XCTAssertEqual(freshRepository.downloads.first?.id, download.id)
    XCTAssertEqual(freshRepository.downloads.first?.layerID, download.layerID)
    XCTAssertEqual(freshRepository.downloads.first?.md5, download.md5)
    XCTAssertEqual(freshRepository.downloads.first?.fileSize, download.fileSize)
  }

  // MARK: - lastDownloadDate

  func testLastDownloadDate_returnsLatestForLayer() async throws {
    let older = makeDownload(layerID: "shom", downloadDate: Date(timeIntervalSince1970: 1_000_000))
    let newer = makeDownload(layerID: "shom", downloadDate: Date(timeIntervalSince1970: 2_000_000))

    try await repository.save(older)
    try await repository.save(newer)

    let lastDate = repository.lastDownloadDate(for: "shom")
    XCTAssertEqual(lastDate?.timeIntervalSince1970 ?? 0, 2_000_000, accuracy: 1.0)
  }

  func testLastDownloadDate_nilForUnknownLayer() async throws {
    let download = makeDownload(layerID: "shom")
    try await repository.save(download)

    XCTAssertNil(repository.lastDownloadDate(for: "noaa"), "No date should be returned for an unknown layerID.")
  }

  func testLastDownloadDate_doesNotCrossLayers() async throws {
    let shomDate = Date(timeIntervalSince1970: 5_000_000)
    let noaaDate = Date(timeIntervalSince1970: 1_000_000)

    try await repository.save(makeDownload(layerID: "shom", downloadDate: shomDate))
    try await repository.save(makeDownload(layerID: "noaa", downloadDate: noaaDate))

    XCTAssertEqual(repository.lastDownloadDate(for: "shom")?.timeIntervalSince1970 ?? 0, 5_000_000, accuracy: 1.0)
    XCTAssertEqual(repository.lastDownloadDate(for: "noaa")?.timeIntervalSince1970 ?? 0, 1_000_000, accuracy: 1.0)
  }

  func testFetchLastDownloadDate_queriesDatabaseDirectly() async throws {
    let shomDate = Date(timeIntervalSince1970: 3_000_000)
    try await repository.save(makeDownload(layerID: "shom", downloadDate: shomDate))

    let dbDate = try await repository.fetchLastDownloadDate(for: "shom")
    XCTAssertEqual(dbDate?.timeIntervalSince1970 ?? 0, 3_000_000, accuracy: 1.0)

    let unknownDate = try await repository.fetchLastDownloadDate(for: "unknown")
    XCTAssertNil(unknownDate)
  }
}
