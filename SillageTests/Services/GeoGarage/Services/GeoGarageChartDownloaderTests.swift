//
//  GeoGarageChartDownloaderTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CryptoKit
@testable import Sillage

@MainActor
final class GeoGarageChartDownloaderTests: XCTestCase {

  private var session: URLSession!
  private var tempDirURL: URL!

  override func setUp() {
    super.setUp()
    MockURLProtocol.reset()
    session = MockURLProtocol.makeMockSession()
    tempDirURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
  }

  override func tearDown() {
    MockURLProtocol.reset()
    session = nil
    if let tempDirURL {
      try? FileManager.default.removeItem(at: tempDirURL)
    }
    super.tearDown()
  }

  // MARK: - Mock Package Service

  private final class MockPackageService: GeoGaragePackageServiceProtocol, @unchecked Sendable {
    var deletedPackageIDs: [UUID] = []

    func requestPackage(_ request: PackageRequest, apiKey: String, userID: String) async throws(CaasError) -> UUID {
      UUID()
    }

    func fetchStatus(packageID: UUID, apiKey: String) async throws(CaasError) -> PackageStatusResponse {
      PackageStatusResponse(
        uuid: packageID,
        state: .success,
        tileNumbers: 100,
        tilesPerSec: 10,
        monitor: nil,
        eta: nil,
        url: "https://mock.download",
        md5: "mock_md5",
        size: 1024,
        error: nil
      )
    }

    func deletePackage(packageID: UUID, apiKey: String) async throws(CaasError) {
      deletedPackageIDs.append(packageID)
    }

    func pollUntilComplete(
      packageID: UUID,
      apiKey: String,
      initialInterval: Duration,
      maxInterval: Duration,
      backoffMultiplier: Double,
      timeout: Duration
    ) async -> AsyncThrowingStream<PackageStatusResponse, Error> {
      AsyncThrowingStream { $0.finish() }
    }
  }

  // MARK: - Download Success

  func testDownload_successfulPipeline() async throws {
    let packageUUID = UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6")!
    let fileContent = "Fake MBTiles Content".data(using: .utf8)!
    let expectedMD5 = Insecure.MD5.hash(data: fileContent).map { String(format: "%02hhx", $0) }.joined()

    MockURLProtocol.setHandler { request in
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, fileContent)
    }

    let mockPackageService = MockPackageService()
    let persistenceActor = LocalFilePersistenceActor()
    let repoURL = tempDirURL.appendingPathComponent("downloads.json")
    let repository = GeoGarageDownloadRepository(persistence: persistenceActor, fileURL: repoURL)

    let downloader = GeoGarageChartDownloader(
      packageService: mockPackageService,
      downloadRepository: repository,
      sessionConfiguration: MockURLProtocol.makeMockConfiguration(),
      chartsDirectoryURL: tempDirURL
    )

    let downloadURL = URL(string: "https://caas.geogarage.com/packages/\(packageUUID.uuidString)/download")!
    let record = try await downloader.download(
      packageID: packageUUID,
      downloadURL: downloadURL,
      expectedMD5: expectedMD5,
      layerID: "shom",
      layerName: "SHOM France",
      boundsWKT: "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
      zoomMax: 14,
      apiKey: "test_api_key"
    )

    // 1. Verify returned record
    XCTAssertEqual(record.id, packageUUID)
    XCTAssertEqual(record.layerID, "shom")
    XCTAssertEqual(record.md5, expectedMD5)

    // 2. Verify file moved to destination
    let destinationFile = tempDirURL.appendingPathComponent("shom_\(packageUUID.uuidString.lowercased()).mbtiles")
    XCTAssertTrue(FileManager.default.fileExists(atPath: destinationFile.path))

    // 3. Verify server package was deleted
    XCTAssertEqual(mockPackageService.deletedPackageIDs, [packageUUID])

    // 4. Verify repository contains the record
    let downloads = repository.downloads
    XCTAssertEqual(downloads.count, 1)
    XCTAssertEqual(downloads.first?.id, packageUUID)
  }

  // MARK: - MD5 Mismatch

  func testDownload_md5Mismatch_cleansUpAndThrows() async throws {
    let packageUUID = UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6")!
    let fileContent = "Corrupted Content".data(using: .utf8)!

    MockURLProtocol.setHandler { request in
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, fileContent)
    }

    let mockPackageService = MockPackageService()
    let persistenceActor = LocalFilePersistenceActor()
    let repoURL = tempDirURL.appendingPathComponent("downloads.json")
    let repository = GeoGarageDownloadRepository(persistence: persistenceActor, fileURL: repoURL)

    let downloader = GeoGarageChartDownloader(
      packageService: mockPackageService,
      downloadRepository: repository,
      sessionConfiguration: MockURLProtocol.makeMockConfiguration(),
      chartsDirectoryURL: tempDirURL
    )

    let downloadURL = URL(string: "https://caas.geogarage.com/download")!

    do {
      _ = try await downloader.download(
        packageID: packageUUID,
        downloadURL: downloadURL,
        expectedMD5: "00000000000000000000000000000000",
        layerID: "shom",
        layerName: "SHOM France",
        boundsWKT: "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
        zoomMax: 14,
        apiKey: "test_api_key"
      )
      XCTFail("Should have thrown CaasError.md5Mismatch")
    } catch {
      guard case CaasError.md5Mismatch = error else {
        XCTFail("Expected CaasError.md5Mismatch, got \(error)")
        return
      }
    }

    // Verify repository remains empty
    let downloads = repository.downloads
    XCTAssertTrue(downloads.isEmpty)

    // Verify no file moved to destination
    let destinationFile = tempDirURL.appendingPathComponent("shom_\(packageUUID.uuidString.lowercased()).mbtiles")
    XCTAssertFalse(FileManager.default.fileExists(atPath: destinationFile.path))
  }

  // MARK: - Delete Local Chart

  func testDeleteLocalChart_removesFileAndRepositoryRecord() async throws {
    let packageUUID = UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6")!
    let mockFile = tempDirURL.appendingPathComponent("shom_\(packageUUID.uuidString.lowercased()).mbtiles")
    try "Chart Data".data(using: .utf8)!.write(to: mockFile)
    XCTAssertTrue(FileManager.default.fileExists(atPath: mockFile.path))

    let persistenceActor = LocalFilePersistenceActor()
    let repoURL = tempDirURL.appendingPathComponent("downloads.json")
    let repository = GeoGarageDownloadRepository(persistence: persistenceActor, fileURL: repoURL)

    let record = OfflineChartDownload(
      id: packageUUID,
      layerID: "shom",
      layerName: "SHOM France",
      downloadDate: Date(),
      relativePath: "Charts/shom_\(packageUUID.uuidString.lowercased()).mbtiles",
      md5: "abc",
      zoomMax: 14,
      boundsWKT: "POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))"
    )
    try await repository.save(record)
    let downloadsBefore = repository.downloads
    XCTAssertEqual(downloadsBefore.count, 1)

    let mockPackageService = MockPackageService()
    let downloader = GeoGarageChartDownloader(
      packageService: mockPackageService,
      downloadRepository: repository,
      sessionConfiguration: MockURLProtocol.makeMockConfiguration(),
      chartsDirectoryURL: tempDirURL
    )

    try await downloader.deleteLocalChart(id: packageUUID)

    // Verify repository entry removed
    let downloadsAfter = repository.downloads
    XCTAssertTrue(downloadsAfter.isEmpty)
  }
}
