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

  // MARK: - Helpers

  private func makeRepository(fileName: String = UUID().uuidString + ".json") -> GeoGarageDownloadRepository {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    let persistence = LocalFilePersistenceActor()
    return GeoGarageDownloadRepository(persistence: persistence, fileURL: tempURL)
  }

  private func makeDownload(
    layerID: String = "shom",
    layerName: String = "SHOM France",
    downloadDate: Date = Date()
  ) -> OfflineChartDownload {
    OfflineChartDownload(
      id: UUID(),
      layerID: layerID,
      layerName: layerName,
      downloadDate: downloadDate,
      relativePath: "Charts/\(layerID)_test.mbtiles",
      md5: "d41d8cd98f00b204e9800998ecf8427e",
      zoomMax: 14,
      boundsWKT: "POLYGON((-5.0 47.0, 0.0 47.0, 0.0 50.0, -5.0 50.0, -5.0 47.0))"
    )
  }

  // MARK: - Load

  func testLoad_emptyWhenFileDoesNotExist() async {
    let repo = makeRepository()

    await repo.load()

    XCTAssertTrue(repo.downloads.isEmpty, "A repository without an existing backing file must start empty.")
  }

  // MARK: - Save

  func testSave_appendsNewDownload() async {
    let repo = makeRepository()
    let download = makeDownload()

    await repo.save(download)

    XCTAssertEqual(repo.downloads.count, 1)
    XCTAssertEqual(repo.downloads.first?.id, download.id)
  }

  func testSave_isIdempotent_sameID() async {
    let repo = makeRepository()
    let download = makeDownload()
    let updatedDownload = OfflineChartDownload(
      id: download.id,
      layerID: download.layerID,
      layerName: "Updated Name",
      downloadDate: Date(),
      relativePath: download.relativePath,
      md5: "newmd5",
      zoomMax: 16,
      boundsWKT: download.boundsWKT
    )

    await repo.save(download)
    await repo.save(updatedDownload)

    XCTAssertEqual(repo.downloads.count, 1, "Saving an entry with an existing UUID must update in-place without duplicating.")
    XCTAssertEqual(repo.downloads.first?.layerName, "Updated Name")
    XCTAssertEqual(repo.downloads.first?.md5, "newmd5")
  }

  func testSave_multipleDifferentDownloads() async {
    let repo = makeRepository()
    let d1 = makeDownload(layerID: "shom")
    let d2 = makeDownload(layerID: "noaa")

    await repo.save(d1)
    await repo.save(d2)

    XCTAssertEqual(repo.downloads.count, 2)
  }

  // MARK: - Delete

  func testDelete_removesCorrectEntry() async {
    let repo = makeRepository()
    let d1 = makeDownload(layerID: "shom")
    let d2 = makeDownload(layerID: "noaa")

    await repo.save(d1)
    await repo.save(d2)
    await repo.delete(id: d1.id)

    XCTAssertEqual(repo.downloads.count, 1)
    XCTAssertEqual(repo.downloads.first?.layerID, "noaa")
  }

  func testDelete_noOpOnNonexistentID() async {
    let repo = makeRepository()
    let download = makeDownload()
    await repo.save(download)

    await repo.delete(id: UUID())

    XCTAssertEqual(repo.downloads.count, 1, "Deleting an unknown UUID should not modify existing entries.")
  }

  // MARK: - Persistence (Round-Trip via file)

  func testPersistence_survivesRoundTrip() async {
    let fileName = UUID().uuidString + ".json"
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    let persistence = LocalFilePersistenceActor()
    let download = makeDownload()

    // Write phase
    let repoWrite = GeoGarageDownloadRepository(persistence: persistence, fileURL: tempURL)
    await repoWrite.save(download)

    // Read phase with new instance pointing to same file
    let repoRead = GeoGarageDownloadRepository(persistence: persistence, fileURL: tempURL)
    await repoRead.load()

    XCTAssertEqual(repoRead.downloads.count, 1)
    XCTAssertEqual(repoRead.downloads.first?.id, download.id)
    XCTAssertEqual(repoRead.downloads.first?.layerID, download.layerID)
    XCTAssertEqual(repoRead.downloads.first?.md5, download.md5)

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  // MARK: - State Consistency on Disk Failure

  func testSave_whenDiskWriteFails_inMemoryStateIsNotModified() async {
    // Point repository to an impossible path to force persistence.save() to throw
    let invalidURL = URL(fileURLWithPath: "/dev/null/invalid_dir/geogarage_downloads.json")
    let persistence = LocalFilePersistenceActor()
    let repo = GeoGarageDownloadRepository(persistence: persistence, fileURL: invalidURL)

    let download = makeDownload()
    await repo.save(download)

    XCTAssertTrue(
      repo.downloads.isEmpty,
      "If disk persistence fails, in-memory state must NOT be modified (disk is the single source of truth)."
    )
  }

  func testDelete_whenDiskWriteFails_inMemoryStateIsNotModified() async {
    let fileName = UUID().uuidString + ".json"
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    let persistence = LocalFilePersistenceActor()
    let repo = GeoGarageDownloadRepository(persistence: persistence, fileURL: tempURL)

    let download = makeDownload()
    await repo.save(download)
    XCTAssertEqual(repo.downloads.count, 1)

    let invalidURL = URL(fileURLWithPath: "/dev/null/invalid_dir/geogarage_downloads.json")
    let failingRepo = GeoGarageDownloadRepository(persistence: persistence, fileURL: invalidURL)

    // Attempt delete on invalid path repo
    await failingRepo.delete(id: download.id)
    XCTAssertTrue(failingRepo.downloads.isEmpty, "Delete failure on disk must not modify in-memory state.")

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  // MARK: - lastDownloadDate

  func testLastDownloadDate_returnsLatestForLayer() async {
    let repo = makeRepository()
    let older = makeDownload(layerID: "shom", downloadDate: Date(timeIntervalSince1970: 1_000_000))
    let newer = makeDownload(layerID: "shom", downloadDate: Date(timeIntervalSince1970: 2_000_000))

    await repo.save(older)
    await repo.save(newer)

    let lastDate = repo.lastDownloadDate(for: "shom")
    XCTAssertEqual(lastDate?.timeIntervalSince1970 ?? 0, 2_000_000, accuracy: 1.0)
  }

  func testLastDownloadDate_nilForUnknownLayer() async {
    let repo = makeRepository()
    let download = makeDownload(layerID: "shom")
    await repo.save(download)

    XCTAssertNil(repo.lastDownloadDate(for: "noaa"), "No date should be returned for an unknown layerID.")
  }

  func testLastDownloadDate_doesNotCrossLayers() async {
    let repo = makeRepository()
    let shomDate = Date(timeIntervalSince1970: 5_000_000)
    let noaaDate = Date(timeIntervalSince1970: 1_000_000)

    await repo.save(makeDownload(layerID: "shom", downloadDate: shomDate))
    await repo.save(makeDownload(layerID: "noaa", downloadDate: noaaDate))

    XCTAssertEqual(repo.lastDownloadDate(for: "shom")?.timeIntervalSince1970 ?? 0, 5_000_000, accuracy: 1.0)
    XCTAssertEqual(repo.lastDownloadDate(for: "noaa")?.timeIntervalSince1970 ?? 0, 1_000_000, accuracy: 1.0)
  }
}
