//
//  OfflineChartDetailViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
final class OfflineChartDetailViewModelTests: XCTestCase {

  // MARK: - Mocks

  @MainActor
  private final class MockDownloadRepository: GeoGarageDownloadRepositoryProtocol, @unchecked Sendable {
    var downloads: [OfflineChartDownload] = []
    var shouldThrowOnSave: Bool = false
    var shouldThrowOnDelete: Bool = false

    func load() async {}

    func save(_ download: OfflineChartDownload) async throws {
      if shouldThrowOnSave {
        throw NSError(domain: "DiskError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated disk write failure"])
      }
      if let index = downloads.firstIndex(where: { $0.id == download.id }) {
        downloads[index] = download
      } else {
        downloads.append(download)
      }
    }

    func delete(id: UUID) async throws {
      if shouldThrowOnDelete {
        throw NSError(domain: "DiskError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Simulated disk deletion failure"])
      }
      downloads.removeAll { $0.id == id }
    }

    func lastDownloadDate(for layerID: String) -> Date? {
      downloads.filter { $0.layerID == layerID }.map(\.downloadDate).max()
    }
  }

  // MARK: - Test Helpers

  private func waitForInspection(on viewModel: OfflineChartDetailViewModel, timeoutMs: Int = 2000) async throws {
    let start = Date()
    while viewModel.fileStatus == .checking {
      if Date().timeIntervalSince(start) > Double(timeoutMs) / 1000.0 {
        XCTFail("Timed out waiting for OfflineChartDetailViewModel inspection")
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  // MARK: - Tests

  func testInitializationWithMissingFile_SetsNilSizeAndFileMissingStatus() async throws {
    let mockRepo = MockDownloadRepository()
    let chartID = UUID()

    let nonExistentRecord = OfflineChartDownload(
      id: chartID,
      layerID: "shom",
      layerName: "SHOM Atlantic",
      downloadDate: Date(),
      relativePath: "Charts/non_existent_\(UUID().uuidString).mbtiles",
      md5: "e10adc3949ba59abbe56e057f20f883e",
      zoomMax: 14,
      boundsWKT: "POLYGON((-5.0 48.0, -4.0 48.0, -4.0 49.0, -5.0 49.0, -5.0 48.0))"
    )
    try await mockRepo.save(nonExistentRecord)

    let viewModel = OfflineChartDetailViewModel(chartID: chartID, downloadRepository: mockRepo)
    try await waitForInspection(on: viewModel)

    // Strict Zero Dummy Value rule: must be nil, NOT 0
    XCTAssertNil(viewModel.fileSizeBytes, "Missing physical file must result in strictly nil fileSizeBytes")
    XCTAssertEqual(viewModel.fileStatus, .fileMissing, "Missing physical file must set fileStatus to .fileMissing")
    XCTAssertEqual(viewModel.chartName, "SHOM Atlantic")
    XCTAssertEqual(viewModel.layerID, "shom")
    XCTAssertEqual(viewModel.maxZoom, 14)
  }

  func testInitializationWithExistingFile_SetsCorrectSizeAndReadyStatus() async throws {
    let mockRepo = MockDownloadRepository()
    let chartID = UUID()

    // Create a temporary dummy MBTiles file in Documents/Charts
    guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      XCTFail("Documents directory unavailable")
      return
    }

    let chartsDir = documentsDir.appendingPathComponent("Charts")
    try FileManager.default.createDirectory(at: chartsDir, withIntermediateDirectories: true)

    let fileName = "test_chart_\(chartID.uuidString).mbtiles"
    let fileURL = chartsDir.appendingPathComponent(fileName)
    let sampleData = Data(repeating: 0x42, count: 2048)
    try sampleData.write(to: fileURL)

    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let record = OfflineChartDownload(
      id: chartID,
      layerID: "ukho",
      layerName: "UKHO Solent",
      downloadDate: Date(),
      relativePath: "Charts/\(fileName)",
      md5: "098f6bcd4621d373cade4e832627b4f6",
      zoomMax: 12,
      boundsWKT: "POLYGON((-1.5 50.5, -1.0 50.5, -1.0 51.0, -1.5 51.0, -1.5 50.5))"
    )
    try await mockRepo.save(record)

    let viewModel = OfflineChartDetailViewModel(chartID: chartID, downloadRepository: mockRepo)
    try await waitForInspection(on: viewModel)

    XCTAssertEqual(viewModel.fileSizeBytes, 2048, "Existing file size must match physical size")
    XCTAssertEqual(viewModel.fileStatus, .ready, "Existing file must set fileStatus to .ready")
    XCTAssertEqual(viewModel.chartName, "UKHO Solent")
  }

  func testOffMainActorGeometricParsingAndDDMFormatting() async throws {
    let mockRepo = MockDownloadRepository()
    let chartID = UUID()

    // Bounding box for Brest / Iroise Sea
    let record = OfflineChartDownload(
      id: chartID,
      layerID: "shom",
      layerName: "SHOM Brest",
      downloadDate: Date(),
      relativePath: "Charts/brest.mbtiles",
      md5: "d41d8cd98f00b204e9800998ecf8427e",
      zoomMax: 14,
      boundsWKT: "POLYGON((-5.0 48.0, -4.0 48.0, -4.0 49.0, -5.0 49.0, -5.0 48.0))"
    )
    try await mockRepo.save(record)

    let viewModel = OfflineChartDetailViewModel(chartID: chartID, downloadRepository: mockRepo)
    try await waitForInspection(on: viewModel)

    XCTAssertNotNil(viewModel.geographicBounds, "Geographic bounds must be parsed from WKT")
    XCTAssertNotNil(viewModel.geographicArea, "Geographic area must be computed")
    XCTAssertNotNil(viewModel.formattedCenterCoordinate, "Center coordinate must be formatted in DDM")
    XCTAssertNotNil(viewModel.formattedSouthWestCoordinate, "South-West coordinate must be formatted in DDM")
    XCTAssertNotNil(viewModel.formattedNorthEastCoordinate, "North-East coordinate must be formatted in DDM")

    // Verify DDM format contains degree and minute symbols
    if let center = viewModel.formattedCenterCoordinate {
      XCTAssertTrue(center.contains("°"), "DDM format must contain degree symbol")
      XCTAssertTrue(center.contains("'"), "DDM format must contain minute symbol")
    }
  }

  func testDeleteChartRemovesRecordFromRepository() async throws {
    let mockRepo = MockDownloadRepository()
    let chartID = UUID()

    let record = OfflineChartDownload(
      id: chartID,
      layerID: "shom",
      layerName: "SHOM Morbihan",
      downloadDate: Date(),
      relativePath: "Charts/morbihan.mbtiles",
      md5: "c4ca4238a0b923820dcc509a6f75849b",
      zoomMax: 14,
      boundsWKT: ""
    )
    try await mockRepo.save(record)

    let viewModel = OfflineChartDetailViewModel(chartID: chartID, downloadRepository: mockRepo)
    try await viewModel.deleteChart()

    let remaining = mockRepo.downloads.first(where: { $0.id == chartID })
    XCTAssertNil(remaining, "deleteChart must remove the record from repository")
  }

  // MARK: - Edit Mode & Renaming Tests

  func testStartAndCancelEditing_Lifecycle() async throws {
    let mockRepo = MockDownloadRepository()
    let chartID = UUID()

    let record = OfflineChartDownload(
      id: chartID,
      layerID: "shom",
      layerName: "SHOM Atlantic",
      downloadDate: Date(),
      relativePath: "Charts/shom.mbtiles",
      md5: "abc",
      zoomMax: 14,
      boundsWKT: ""
    )
    try await mockRepo.save(record)

    let viewModel = OfflineChartDetailViewModel(chartID: chartID, downloadRepository: mockRepo)
    try await waitForInspection(on: viewModel)

    XCTAssertFalse(viewModel.isEditing)
    XCTAssertEqual(viewModel.chartName, "SHOM Atlantic")

    viewModel.startEditing()
    XCTAssertTrue(viewModel.isEditing)
    XCTAssertEqual(viewModel.editableName, "SHOM Atlantic")

    viewModel.editableName = "Temporary Modification"
    viewModel.cancelEditing()

    XCTAssertFalse(viewModel.isEditing)
    XCTAssertEqual(viewModel.editableName, "")
    XCTAssertEqual(viewModel.chartName, "SHOM Atlantic")
  }

  func testSaveCustomName_PersistsAndUpdatesDisplayName() async throws {
    let mockRepo = MockDownloadRepository()
    let chartID = UUID()

    let record = OfflineChartDownload(
      id: chartID,
      layerID: "shom",
      layerName: "SHOM Atlantic",
      downloadDate: Date(),
      relativePath: "Charts/shom.mbtiles",
      md5: "abc",
      zoomMax: 14,
      boundsWKT: ""
    )
    try await mockRepo.save(record)

    let viewModel = OfflineChartDetailViewModel(chartID: chartID, downloadRepository: mockRepo)
    try await waitForInspection(on: viewModel)

    viewModel.startEditing()
    viewModel.editableName = "  Bretagne Sud - Houat  "
    try await viewModel.saveCustomName()

    XCTAssertFalse(viewModel.isEditing)
    XCTAssertEqual(viewModel.chartName, "Bretagne Sud - Houat")
    XCTAssertEqual(viewModel.chartDownload?.customName, "Bretagne Sud - Houat")

    let saved = mockRepo.downloads.first(where: { $0.id == chartID })
    XCTAssertEqual(saved?.customName, "Bretagne Sud - Houat")
    XCTAssertEqual(saved?.layerName, "SHOM Atlantic", "Original layerName must be preserved")
  }

  func testSaveCustomName_EmptyOrMatchingLayerNameResetsToNil() async throws {
    let mockRepo = MockDownloadRepository()
    let chartID = UUID()

    let record = OfflineChartDownload(
      id: chartID,
      layerID: "shom",
      layerName: "SHOM Atlantic",
      downloadDate: Date(),
      relativePath: "Charts/shom.mbtiles",
      md5: "abc",
      zoomMax: 14,
      boundsWKT: "",
      customName: "Existing Custom Name"
    )
    try await mockRepo.save(record)

    let viewModel = OfflineChartDetailViewModel(chartID: chartID, downloadRepository: mockRepo)
    try await waitForInspection(on: viewModel)

    XCTAssertEqual(viewModel.chartName, "Existing Custom Name")

    // Saving matching layer name resets customName to nil
    viewModel.startEditing()
    viewModel.editableName = "SHOM Atlantic"
    try await viewModel.saveCustomName()

    XCTAssertNil(viewModel.chartDownload?.customName)
    XCTAssertEqual(viewModel.chartName, "SHOM Atlantic")

    // Saving empty/whitespace resets customName to nil
    viewModel.startEditing()
    viewModel.editableName = "   "
    try await viewModel.saveCustomName()

    XCTAssertNil(viewModel.chartDownload?.customName)
    XCTAssertEqual(viewModel.chartName, "SHOM Atlantic")
  }

  func testIsSaveDisabled_Validation() async throws {
    let mockRepo = MockDownloadRepository()
    let chartID = UUID()

    let record = OfflineChartDownload(
      id: chartID,
      layerID: "shom",
      layerName: "SHOM Atlantic",
      downloadDate: Date(),
      relativePath: "Charts/shom.mbtiles",
      md5: "abc",
      zoomMax: 14,
      boundsWKT: ""
    )
    try await mockRepo.save(record)

    let viewModel = OfflineChartDetailViewModel(chartID: chartID, downloadRepository: mockRepo)
    try await waitForInspection(on: viewModel)

    viewModel.startEditing()
    viewModel.editableName = ""
    XCTAssertTrue(viewModel.isSaveDisabled, "Save must be disabled when name is empty")

    viewModel.editableName = "   "
    XCTAssertTrue(viewModel.isSaveDisabled, "Save must be disabled when name consists only of whitespace")

    viewModel.editableName = "Belle-Île"
    XCTAssertFalse(viewModel.isSaveDisabled, "Save must be enabled for valid text")
  }

  func testSaveCustomName_WhenRepositoryThrows_SetsErrorMessageAndRethrows() async throws {
    let mockRepo = MockDownloadRepository()
    let chartID = UUID()

    let record = OfflineChartDownload(
      id: chartID,
      layerID: "shom",
      layerName: "SHOM Atlantic",
      downloadDate: Date(),
      relativePath: "Charts/shom.mbtiles",
      md5: "abc",
      zoomMax: 14,
      boundsWKT: ""
    )
    try await mockRepo.save(record)

    let viewModel = OfflineChartDetailViewModel(chartID: chartID, downloadRepository: mockRepo)
    try await waitForInspection(on: viewModel)

    mockRepo.shouldThrowOnSave = true

    viewModel.startEditing()
    viewModel.editableName = "Corrupted Destination"

    do {
      try await viewModel.saveCustomName()
      XCTFail("saveCustomName must rethrow if repository save fails")
    } catch {
      XCTAssertEqual(viewModel.errorMessage, "Simulated disk write failure")
    }
  }

  func testDeleteChart_WhenRepositoryThrows_SetsErrorMessageAndRethrows() async throws {
    let mockRepo = MockDownloadRepository()
    let chartID = UUID()

    let record = OfflineChartDownload(
      id: chartID,
      layerID: "shom",
      layerName: "SHOM Atlantic",
      downloadDate: Date(),
      relativePath: "Charts/shom.mbtiles",
      md5: "abc",
      zoomMax: 14,
      boundsWKT: ""
    )
    try await mockRepo.save(record)

    let viewModel = OfflineChartDetailViewModel(chartID: chartID, downloadRepository: mockRepo)
    try await waitForInspection(on: viewModel)

    mockRepo.shouldThrowOnDelete = true

    do {
      try await viewModel.deleteChart()
      XCTFail("deleteChart must rethrow if repository delete fails")
    } catch {
      XCTAssertEqual(viewModel.errorMessage, "Simulated disk deletion failure")
    }
  }
}
