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

  override func setUp() async throws {
    try await super.setUp()
    MockURLProtocol.reset()
    session = MockURLProtocol.makeMockSession()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    tempDirURL = dir
  }

  override func tearDown() async throws {
    MockURLProtocol.reset()
    session = nil
    if let tempDirURL {
      try? FileManager.default.removeItem(at: tempDirURL)
    }
    try await super.tearDown()
  }

  // MARK: - Mock Package Service

  private final class MockPackageService: GeoGaragePackageServiceProtocol, @unchecked Sendable {
    var deletedPackageIDs: [UUID] = []

    func requestPackage(_ request: PackageRequest, accessToken: String) async throws(CaasError) -> UUID {
      UUID()
    }

    func fetchStatus(packageID: UUID, accessToken: String) async throws(CaasError) -> PackageStatusResponse {
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

    func deletePackage(packageID: UUID, accessToken: String) async throws(CaasError) {
      deletedPackageIDs.append(packageID)
    }

    func pollUntilComplete(
      packageID: UUID,
      accessToken: String,
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
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)

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
      accessToken: "test_access_token"
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
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)

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
        accessToken: "test_access_token"
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
    let packageUUID = try XCTUnwrap(UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6"))
    let mockFile = tempDirURL.appendingPathComponent("shom_\(packageUUID.uuidString.lowercased()).mbtiles")
    let chartData = try XCTUnwrap("Chart Data".data(using: .utf8))
    try chartData.write(to: mockFile)
    XCTAssertTrue(FileManager.default.fileExists(atPath: mockFile.path))

    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)

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

  // MARK: - Deterministic Staging & Orphan Cleanup

  func testDownload_consumesPreStagedFileWithoutNetworkCall() async throws {
    let packageUUID = try XCTUnwrap(UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6"))
    let fileContent = try XCTUnwrap("Pre-staged MBTiles Content".data(using: .utf8))
    let expectedMD5 = Insecure.MD5.hash(data: fileContent).map { String(format: "%02hhx", $0) }.joined()

    let stagingDir = tempDirURL.appendingPathComponent("GeoGarageStaging", isDirectory: true)
    try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
    let stagedFile = stagingDir.appendingPathComponent("\(packageUUID.uuidString.lowercased()).mbtiles")
    try fileContent.write(to: stagedFile)

    MockURLProtocol.setErrorHandler { _ in
      URLError(.notConnectedToInternet)
    }

    let mockPackageService = MockPackageService()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)

    let downloader = GeoGarageChartDownloader(
      packageService: mockPackageService,
      downloadRepository: repository,
      sessionConfiguration: MockURLProtocol.makeMockConfiguration(),
      chartsDirectoryURL: tempDirURL
    )

    let downloadURL = try XCTUnwrap(URL(string: "https://caas.geogarage.com/packages/\(packageUUID.uuidString)/download"))
    let record = try await downloader.download(
      packageID: packageUUID,
      downloadURL: downloadURL,
      expectedMD5: expectedMD5,
      layerID: "shom",
      layerName: "SHOM France",
      boundsWKT: "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
      zoomMax: 14,
      accessToken: "test_access_token"
    )

    XCTAssertEqual(record.id, packageUUID)
    XCTAssertFalse(FileManager.default.fileExists(atPath: stagedFile.path), "Staged file should be moved/cleaned after installation")
    let destinationFile = tempDirURL.appendingPathComponent("shom_\(packageUUID.uuidString.lowercased()).mbtiles")
    XCTAssertTrue(FileManager.default.fileExists(atPath: destinationFile.path))
  }

  func testCleanupOrphanedDownloads_removesUnretainedStagedFiles() async throws {
    let retainedID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let orphanedID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))

    let stagingDir = tempDirURL.appendingPathComponent("GeoGarageStaging", isDirectory: true)
    try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
    let retainedFile = stagingDir.appendingPathComponent("\(retainedID.uuidString.lowercased()).mbtiles")
    let orphanedFile = stagingDir.appendingPathComponent("\(orphanedID.uuidString.lowercased()).mbtiles")
    try Data("retained".utf8).write(to: retainedFile)
    try Data("orphaned".utf8).write(to: orphanedFile)

    let mockPackageService = MockPackageService()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)

    let downloader = GeoGarageChartDownloader(
      packageService: mockPackageService,
      downloadRepository: repository,
      sessionConfiguration: MockURLProtocol.makeMockConfiguration(),
      chartsDirectoryURL: tempDirURL
    )

    await downloader.cleanupOrphanedDownloads(retainingPackageIDs: [retainedID])

    XCTAssertTrue(FileManager.default.fileExists(atPath: retainedFile.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: orphanedFile.path))
  }

  func testDownload_http401_throwsAuthenticationRequiredWithoutStaging() async throws {
    let packageUUID = try XCTUnwrap(UUID(uuidString: "4FA85F64-5717-4562-B3FC-2C963F66AFA6"))
    MockURLProtocol.setHandler { request in
      let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
      return (response, Data("Unauthorized".utf8))
    }

    let mockPackageService = MockPackageService()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let downloader = GeoGarageChartDownloader(
      packageService: mockPackageService,
      downloadRepository: repository,
      sessionConfiguration: MockURLProtocol.makeMockConfiguration(),
      chartsDirectoryURL: tempDirURL
    )

    let downloadURL = try XCTUnwrap(URL(string: "https://caas.geogarage.com/packages/\(packageUUID.uuidString)/download"))
    do {
      _ = try await downloader.download(
        packageID: packageUUID,
        downloadURL: downloadURL,
        expectedMD5: "d41d8cd98f00b204e9800998ecf8427e",
        layerID: "shom",
        layerName: "SHOM France",
        boundsWKT: "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
        zoomMax: 14,
        accessToken: "expired_token"
      )
      XCTFail("Expected CaasError.authenticationRequired")
    } catch {
      XCTAssertEqual(error, .authenticationRequired)
    }

    let stagedFile = tempDirURL
      .appendingPathComponent("GeoGarageStaging", isDirectory: true)
      .appendingPathComponent("\(packageUUID.uuidString.lowercased()).mbtiles")
    XCTAssertFalse(FileManager.default.fileExists(atPath: stagedFile.path))
  }

  func testDownload_http500_throwsRequestFailedWithoutStaging() async throws {
    let packageUUID = try XCTUnwrap(UUID(uuidString: "5FA85F64-5717-4562-B3FC-2C963F66AFA6"))
    MockURLProtocol.setHandler { request in
      let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
      return (response, Data("Server Error".utf8))
    }

    let mockPackageService = MockPackageService()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let downloader = GeoGarageChartDownloader(
      packageService: mockPackageService,
      downloadRepository: repository,
      sessionConfiguration: MockURLProtocol.makeMockConfiguration(),
      chartsDirectoryURL: tempDirURL
    )

    let downloadURL = try XCTUnwrap(URL(string: "https://caas.geogarage.com/packages/\(packageUUID.uuidString)/download"))
    do {
      _ = try await downloader.download(
        packageID: packageUUID,
        downloadURL: downloadURL,
        expectedMD5: "d41d8cd98f00b204e9800998ecf8427e",
        layerID: "shom",
        layerName: "SHOM France",
        boundsWKT: "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
        zoomMax: 14,
        accessToken: "test_access_token"
      )
      XCTFail("Expected CaasError.requestFailed(statusCode: 500)")
    } catch {
      XCTAssertEqual(error, .requestFailed(statusCode: 500))
    }
  }
}
