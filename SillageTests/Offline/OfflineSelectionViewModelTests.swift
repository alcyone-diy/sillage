//
//  OfflineSelectionViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
final class OfflineSelectionViewModelTests: XCTestCase {

  // MARK: - Mocks

  private final class MockChartDownloader: GeoGarageChartDownloaderProtocol, @unchecked Sendable {
    var shouldThrowError: Error?
    var deletedIDs: [UUID] = []
    var downloadedRecord: OfflineChartDownload?

    func download(
      packageID: UUID,
      downloadURL: URL,
      expectedMD5: String,
      layerID: String,
      layerName: String,
      boundsWKT: String,
      zoomMax: Int,
      apiKey: String
    ) async throws(CaasError) -> OfflineChartDownload {
      if shouldThrowError != nil {
        throw CaasError.requestFailed(statusCode: 500)
      }

      if let downloadedRecord {
        return downloadedRecord
      }

      return OfflineChartDownload(
        id: packageID,
        layerID: layerID,
        layerName: layerName,
        downloadDate: Date(),
        relativePath: "Charts/\(packageID.uuidString.lowercased()).mbtiles",
        md5: expectedMD5,
        zoomMax: zoomMax,
        boundsWKT: boundsWKT
      )
    }

    func deleteLocalChart(id: UUID) async throws(CaasError) {
      deletedIDs.append(id)
    }
  }

  private final class MockPackageService: GeoGaragePackageServiceProtocol, @unchecked Sendable {
    var packageIDToReturn = UUID()
    var statusSequence: [PackageStatusResponse] = []
    var shouldThrowOnRequest: Bool = false

    func requestPackage(
      _ request: PackageRequest,
      apiKey: String,
      userID: String
    ) async throws(CaasError) -> UUID {
      if shouldThrowOnRequest {
        throw CaasError.requestFailed(statusCode: 500)
      }
      return packageIDToReturn
    }

    func fetchStatus(packageID: UUID, apiKey: String) async throws(CaasError) -> PackageStatusResponse {
      PackageStatusResponse(
        uuid: packageID,
        state: .success,
        tileNumbers: 100,
        tilesPerSec: 20,
        monitor: "100/100",
        eta: nil,
        url: "https://caas.geogarage.com/downloads/\(packageID.uuidString.lowercased())/chart.mbtiles",
        md5: "d41d8cd98f00b204e9800998ecf8427e",
        size: 1024 * 1024,
        error: nil
      )
    }

    func deletePackage(packageID: UUID, apiKey: String) async throws(CaasError) {}

    func pollUntilComplete(
      packageID: UUID,
      apiKey: String,
      initialInterval: Duration,
      maxInterval: Duration,
      backoffMultiplier: Double,
      timeout: Duration
    ) async -> AsyncThrowingStream<PackageStatusResponse, Error> {
      let statuses = statusSequence.isEmpty ? [
        PackageStatusResponse(
          uuid: packageID,
          state: .progress,
          tileNumbers: 100,
          tilesPerSec: 10,
          monitor: "50/100",
          eta: nil,
          url: nil,
          md5: nil,
          size: nil,
          error: nil
        ),
        PackageStatusResponse(
          uuid: packageID,
          state: .success,
          tileNumbers: 100,
          tilesPerSec: 20,
          monitor: "100/100",
          eta: nil,
          url: "https://caas.geogarage.com/downloads/\(packageID.uuidString.lowercased())/chart.mbtiles",
          md5: "d41d8cd98f00b204e9800998ecf8427e",
          size: 1024 * 1024,
          error: nil
        )
      ] : statusSequence

      return AsyncThrowingStream { continuation in
        let task = Task {
          for status in statuses {
            if Task.isCancelled {
              continuation.finish(throwing: CancellationError())
              return
            }
            continuation.yield(status)
            do {
              try await Task.sleep(nanoseconds: 10_000_000)
            } catch {
              continuation.finish(throwing: CancellationError())
              return
            }
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in
          task.cancel()
        }
      }
    }
  }

  @MainActor
  private final class MockDownloadRepository: GeoGarageDownloadRepositoryProtocol, @unchecked Sendable {
    var downloads: [OfflineChartDownload] = []
    func load() async {}
    func save(_ download: OfflineChartDownload) async {
      downloads.append(download)
    }
    func delete(id: UUID) async {
      downloads.removeAll { $0.id == id }
    }
    func lastDownloadDate(for layerID: String) -> Date? { nil }
  }

  // MARK: - Helpers

  @MainActor
  private func makeSUT(
    downloader: MockChartDownloader? = nil,
    packageService: MockPackageService? = nil,
    downloadRepository: MockDownloadRepository? = nil,
    setupVisibleBounds: Bool = true,
    authenticated: Bool = true
  ) -> (
    sut: OfflineSelectionViewModel,
    downloader: MockChartDownloader,
    packageService: MockPackageService,
    chartVM: ChartViewModel,
    downloadRepo: MockDownloadRepository,
    prefs: PreferencesService
  ) {
    let downloader = downloader ?? MockChartDownloader()
    let packageService = packageService ?? MockPackageService()
    let downloadRepository = downloadRepository ?? MockDownloadRepository()
    let preferences = PreferencesService()
    if authenticated {
      preferences.geoGarageCustomerID = "cust123"
    } else {
      preferences.geoGarageCustomerID = nil
    }

    let authService = MockGeoGarageAuthService()
    let posService = MockPositioningService()
    let dampService = InstrumentDampingService(positioningService: posService)
    let permService = PermissionService(positioningService: posService, notificationService: LocalNotificationService())
    let bgMonService = DefaultBackgroundMonitoringService(positioningService: posService)
    let anchorService = AnchorService(
      positioningService: posService,
      preferencesService: preferences,
      notificationService: LocalNotificationService(),
      permissionService: permService,
      backgroundMonitoringService: bgMonService
    )
    let anchorVM = AnchorViewModel(anchorService: anchorService)
    let chartVM = ChartViewModel(
      positioningService: posService,
      instrumentDampingService: dampService,
      preferencesService: preferences,
      authService: authService,
      anchorService: anchorService,
      anchorViewModel: anchorVM,
      waypointService: nil,
      messageService: MessageService()
    )

    if setupVisibleBounds {
      chartVM.currentVisibleBounds = GeographicBoundingBox(
        southWest: CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0),
        northEast: CLLocationCoordinate2D(latitude: 48.0, longitude: -2.0)
      )
    }

    let sut = OfflineSelectionViewModel(
      downloader: downloader,
      packageService: packageService,
      downloadRepository: downloadRepository,
      preferencesService: preferences,
      chartViewModel: chartVM,
      offlineMapManager: MockOfflineMapManager()
    )

    return (sut, downloader, packageService, chartVM, downloadRepository, preferences)
  }

  // MARK: - Selection State Tests

  func testStartDownloadResetsSelectionStateSynchronously() {
    let (viewModel, _, _, _, _, _) = makeSUT()

    viewModel.isSelectionModeActive = true
    let bounds = GeographicBoundingBox(southWest: .init(latitude: 44, longitude: 0), northEast: .init(latitude: 45, longitude: 1))
    viewModel.updateBoundingBox(bounds)
    viewModel.updateCropRect(CGRect(x: 0, y: 0, width: 100, height: 100))

    viewModel.startDownload(chartSource: nil)

    XCTAssertFalse(viewModel.isSelectionModeActive, "isSelectionModeActive should be false immediately after startDownload")
    XCTAssertNil(viewModel.selectedBounds, "selectedBounds should be reset")
    XCTAssertNil(viewModel.cropRect, "cropRect should be reset")
  }

  func testInitialState_isIdle() {
    let (sut, _, _, _, _, _) = makeSUT()
    XCTAssertEqual(sut.downloadPhase, .idle)
    XCTAssertFalse(sut.isDownloading)
  }

  func testStartDownload_withoutVisibleBounds_setsFailedState() {
    let (sut, _, _, chartVM, _, _) = makeSUT(setupVisibleBounds: false)
    chartVM.currentVisibleBounds = nil

    sut.startDownload(apiKey: "token123", customerID: "cust123")

    if case .failed(let error) = sut.downloadPhase {
      XCTAssertFalse(error.isEmpty)
    } else {
      XCTFail("Expected .failed state when visible bounds are missing, got \(sut.downloadPhase)")
    }
  }

  func testStartDownload_unauthenticated_setsFailedState() {
    let (sut, _, _, _, _, _) = makeSUT(authenticated: false)

    sut.startDownload(chartSource: nil)

    if case .failed(let error) = sut.downloadPhase {
      XCTAssertTrue(error.contains("authenticated"))
    } else {
      XCTFail("Expected .failed state when customer ID is missing")
    }
  }

  func testStartDownload_transitionsThroughPhasesToCompleted_andPersistsPendingState() async throws {
    let downloader = MockChartDownloader()
    let packageService = MockPackageService()
    let downloadID = UUID()
    packageService.packageIDToReturn = downloadID

    let mockRecord = OfflineChartDownload(
      id: downloadID,
      layerID: "shom",
      layerName: "SHOM",
      downloadDate: Date(),
      relativePath: "Charts/\(downloadID.uuidString.lowercased()).mbtiles",
      md5: "d41d8cd98f00b204e9800998ecf8427e",
      zoomMax: 14,
      boundsWKT: "POLYGON((-3.0 47.0, -2.0 47.0, -2.0 48.0, -3.0 48.0, -3.0 47.0))"
    )
    downloader.downloadedRecord = mockRecord

    let (sut, _, _, _, _, prefs) = makeSUT(downloader: downloader, packageService: packageService)

    sut.startDownload(apiKey: "token123", customerID: "cust123")
    XCTAssertEqual(sut.downloadPhase, .requesting)
    XCTAssertTrue(sut.isDownloading)

    // Wait for the pipeline tasks to complete
    for _ in 0..<100 {
      if case .completed = sut.downloadPhase { break }
      try await Task.sleep(nanoseconds: 10_000_000) // 10ms
    }

    XCTAssertEqual(sut.downloadPhase, .completed(mockRecord))
    XCTAssertFalse(sut.isDownloading)
    XCTAssertNil(prefs.pendingCAASDownload, "Pending download must be cleared after completion")
  }

  func testStartDownload_whenErrorOccurs_setsFailedState_andClearsPendingState() async throws {
    let packageService = MockPackageService()
    packageService.shouldThrowOnRequest = true

    let (sut, _, _, _, _, prefs) = makeSUT(packageService: packageService)

    sut.startDownload(apiKey: "token123", customerID: "cust123")

    for _ in 0..<100 {
      if case .failed = sut.downloadPhase { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    if case .failed = sut.downloadPhase {
      XCTAssertFalse(sut.isDownloading)
    } else {
      XCTFail("Expected .failed state, got \(sut.downloadPhase)")
    }
    XCTAssertNil(prefs.pendingCAASDownload, "Pending download must be cleared on error")
  }

  func testCancelDownload_cancelsTask_setsCancelledState_andClearsPendingState() {
    let (sut, _, _, _, _, prefs) = makeSUT()

    sut.startDownload(apiKey: "token123", customerID: "cust123")
    XCTAssertTrue(sut.isDownloading)

    sut.cancelDownload()

    XCTAssertEqual(sut.downloadPhase, .cancelled)
    XCTAssertFalse(sut.isDownloading)
    XCTAssertNil(prefs.pendingCAASDownload, "Pending download must be cleared on cancel")
  }

  func testResumePendingDownloadIfNeeded_resumesUnfinishedDownload() async throws {
    let downloader = MockChartDownloader()
    let packageService = MockPackageService()
    let downloadID = UUID()
    packageService.packageIDToReturn = downloadID

    let (sut, _, _, _, _, prefs) = makeSUT(downloader: downloader, packageService: packageService)

    let pending = PendingCAASDownload(
      packageID: downloadID,
      layerID: "shom",
      layerName: "SHOM France",
      boundsWKT: "POLYGON((-3 47, -2 47, -2 48, -3 48, -3 47))",
      zoomMax: 14,
      createdAt: Date()
    )
    prefs.pendingCAASDownload = pending

    await sut.resumePendingDownloadIfNeeded()

    // Wait for the pipeline tasks to complete
    for _ in 0..<100 {
      if case .completed = sut.downloadPhase { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    if case .completed(let record) = sut.downloadPhase {
      XCTAssertEqual(record.id, downloadID)
    } else {
      XCTFail("Expected completed state, got \(sut.downloadPhase)")
    }
    XCTAssertNil(prefs.pendingCAASDownload)
  }

  func testResumePendingDownloadIfNeeded_skipsIfAlreadyCompletedInRepository() async throws {
    let downloadID = UUID()
    let downloadRepo = MockDownloadRepository()
    let existingRecord = OfflineChartDownload(
      id: downloadID,
      layerID: "shom",
      layerName: "SHOM France",
      downloadDate: Date(),
      relativePath: "Charts/\(downloadID.uuidString.lowercased()).mbtiles",
      md5: "d41d8cd98f00b204e9800998ecf8427e",
      zoomMax: 14,
      boundsWKT: "POLYGON((-3 47, -2 47, -2 48, -3 48, -3 47))"
    )
    downloadRepo.downloads = [existingRecord]

    let (sut, _, _, _, _, prefs) = makeSUT(downloadRepository: downloadRepo)

    let pending = PendingCAASDownload(
      packageID: downloadID,
      layerID: "shom",
      layerName: "SHOM France",
      boundsWKT: "POLYGON((-3 47, -2 47, -2 48, -3 48, -3 47))",
      zoomMax: 14,
      createdAt: Date()
    )
    prefs.pendingCAASDownload = pending

    await sut.resumePendingDownloadIfNeeded()

    // Should immediately clear pending without downloading again
    XCTAssertNil(prefs.pendingCAASDownload)
    XCTAssertEqual(sut.downloadPhase, .idle)
  }

  func testDeleteDownload_callsDownloader() async throws {
    let downloader = MockChartDownloader()
    let downloadRepo = MockDownloadRepository()
    let download = OfflineChartDownload(
      id: UUID(),
      layerID: "shom",
      layerName: "Test Chart",
      downloadDate: Date(),
      relativePath: "Charts/test.mbtiles",
      md5: "md5hash",
      zoomMax: 14,
      boundsWKT: "POLYGON(...)"
    )
    downloadRepo.downloads = [download]

    let (sut, _, _, _, _, _) = makeSUT(downloader: downloader, downloadRepository: downloadRepo)

    try await sut.deleteDownload(download)

    XCTAssertEqual(downloader.deletedIDs.count, 1)
    XCTAssertEqual(downloader.deletedIDs.first, download.id)
  }
}

