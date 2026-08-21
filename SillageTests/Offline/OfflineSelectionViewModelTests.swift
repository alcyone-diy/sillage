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
      if let error = shouldThrowError {
        if let caas = error as? CaasError {
          throw caas
        }
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
    var shouldThrowOnRequest: Error?

    func requestPackage(
      _ request: PackageRequest,
      apiKey: String,
      userID: String
    ) async throws(CaasError) -> UUID {
      if let error = shouldThrowOnRequest {
        if let caas = error as? CaasError {
          throw caas
        }
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

  @MainActor
  private final class MockNetworkMonitorService: NetworkMonitorServiceProtocol, @unchecked Sendable {
    var isConnected: Bool = true
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    func setConnected(_ connected: Bool) {
      self.isConnected = connected
      for cont in continuations.values {
        cont.yield(connected)
      }
    }

    func connectionStream() -> AsyncStream<Bool> {
      let id = UUID()
      return AsyncStream { [weak self] continuation in
        guard let self = self else {
          continuation.finish()
          return
        }
        continuation.yield(self.isConnected)
        self.continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
          Task { @MainActor [weak self] in
            self?.continuations.removeValue(forKey: id)
          }
        }
      }
    }
  }

  // MARK: - Helpers

  @MainActor
  private func makeSUT(
    downloader: MockChartDownloader? = nil,
    packageService: MockPackageService? = nil,
    downloadRepository: MockDownloadRepository? = nil,
    networkMonitor: MockNetworkMonitorService? = nil,
    customDownloadService: GeoGarageDownloadServiceProtocol? = nil,
    setupVisibleBounds: Bool = true,
    authenticated: Bool = true
  ) -> (
    sut: OfflineSelectionViewModel,
    downloadService: GeoGarageDownloadServiceProtocol,
    downloader: MockChartDownloader,
    packageService: MockPackageService,
    chartVM: ChartViewModel,
    downloadRepo: MockDownloadRepository,
    networkMonitor: MockNetworkMonitorService,
    prefs: PreferencesService
  ) {
    let downloader = downloader ?? MockChartDownloader()
    let packageService = packageService ?? MockPackageService()
    let downloadRepository = downloadRepository ?? MockDownloadRepository()
    let networkMonitor = networkMonitor ?? MockNetworkMonitorService()
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

    let downloadService: GeoGarageDownloadServiceProtocol = customDownloadService ?? GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: downloadRepository,
      preferencesService: preferences,
      networkMonitor: networkMonitor
    )

    let sut = OfflineSelectionViewModel(
      downloadService: downloadService,
      downloadRepository: downloadRepository,
      preferencesService: preferences,
      chartViewModel: chartVM,
      offlineMapManager: MockOfflineMapManager(),
      downloader: downloader
    )

    return (sut, downloadService, downloader, packageService, chartVM, downloadRepository, networkMonitor, preferences)
  }

  // MARK: - Selection State Tests

  func testStartDownloadResetsSelectionStateSynchronously() {
    let (viewModel, _, _, _, _, _, _, _) = makeSUT()

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
    let (sut, _, _, _, _, _, _, _) = makeSUT()
    XCTAssertEqual(sut.downloadPhase, .idle)
    XCTAssertFalse(sut.isDownloading)
  }

  func testStartDownload_withoutVisibleBounds_setsFailedState() {
    let (sut, _, _, _, chartVM, _, _, _) = makeSUT(setupVisibleBounds: false)
    chartVM.currentVisibleBounds = nil

    sut.startDownload(apiKey: "token123", customerID: "cust123")

    if case .failed(let error) = sut.downloadPhase {
      XCTAssertFalse(error.isEmpty)
      XCTAssertTrue(error.contains("viewport") || error.contains("zoom") || error.contains("Pan"))
    } else {
      XCTFail("Expected .failed state when visible bounds are missing, got \(sut.downloadPhase)")
    }
    XCTAssertFalse(sut.isDownloading)
  }

  func testStartDownload_unauthenticated_setsFailedState() {
    let (sut, _, _, _, _, _, _, _) = makeSUT(authenticated: false)

    sut.startDownload(chartSource: nil)

    if case .failed(let error) = sut.downloadPhase {
      XCTAssertTrue(error.contains("authenticated") || error.contains("login"))
    } else {
      XCTFail("Expected .failed state when customer ID is missing, got \(sut.downloadPhase)")
    }
    XCTAssertFalse(sut.isDownloading)
  }

  func testStartDownload_offline_persistsPendingStateAndEntersWaitingForNetwork() async throws {
    let networkMonitor = MockNetworkMonitorService()
    networkMonitor.isConnected = false

    let (sut, _, _, _, _, _, _, prefs) = makeSUT(networkMonitor: networkMonitor)

    sut.startDownload(apiKey: "token123", customerID: "cust123")

    for _ in 0..<100 {
      if case .waitingForNetwork = sut.downloadPhase { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    if case .waitingForNetwork = sut.downloadPhase {
      XCTAssertTrue(sut.isDownloading)
    } else {
      XCTFail("Expected .waitingForNetwork state, got \(sut.downloadPhase)")
    }

    XCTAssertNotNil(prefs.pendingCAASDownload, "Pending download must be persisted synchronously before network check")
    XCTAssertNil(prefs.pendingCAASDownload?.packageID, "PackageID must be nil when queued offline")
  }

  func testStartDownload_offline_autoResumesWhenNetworkReconnects() async throws {
    let networkMonitor = MockNetworkMonitorService()
    networkMonitor.isConnected = false

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

    let (sut, _, _, _, _, _, _, prefs) = makeSUT(
      downloader: downloader,
      packageService: packageService,
      networkMonitor: networkMonitor
    )

    sut.startDownload(apiKey: "token123", customerID: "cust123")

    for _ in 0..<100 {
      if case .waitingForNetwork = sut.downloadPhase { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertEqual(sut.downloadPhase, .waitingForNetwork(message: String(localized: "Waiting for network connection…")))
    XCTAssertNotNil(prefs.pendingCAASDownload)

    // Reconnect network
    networkMonitor.setConnected(true)

    // Wait for the pipeline to finish
    for _ in 0..<150 {
      if case .completed = sut.downloadPhase { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertEqual(sut.downloadPhase, .completed(mockRecord))
    XCTAssertNil(prefs.pendingCAASDownload, "Pending download must be cleared after completion")
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

    let (sut, _, _, _, _, _, _, prefs) = makeSUT(downloader: downloader, packageService: packageService)

    sut.startDownload(apiKey: "token123", customerID: "cust123")

    // Wait for the pipeline tasks to complete
    for _ in 0..<100 {
      if case .completed = sut.downloadPhase { break }
      try await Task.sleep(nanoseconds: 10_000_000) // 10ms
    }

    XCTAssertEqual(sut.downloadPhase, .completed(mockRecord))
    XCTAssertFalse(sut.isDownloading)
    XCTAssertNil(prefs.pendingCAASDownload, "Pending download must be cleared after completion")
  }

  func testStartDownload_whenFatalErrorOccurs_setsFailedState_andClearsPendingState() async throws {
    let packageService = MockPackageService()
    packageService.shouldThrowOnRequest = CaasError.requestFailed(statusCode: 500)

    let (sut, _, _, _, _, _, _, prefs) = makeSUT(packageService: packageService)

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
    XCTAssertNil(prefs.pendingCAASDownload, "Pending download must be cleared on fatal server error")
  }

  func testStartDownload_whenConnectivityErrorOccurs_entersWaitingState_andRetainsPendingState() async throws {
    let packageService = MockPackageService()
    packageService.shouldThrowOnRequest = CaasError.networkError(underlying: "The Internet connection appears to be offline.")

    let (sut, _, _, _, _, _, _, prefs) = makeSUT(packageService: packageService)

    sut.startDownload(apiKey: "token123", customerID: "cust123")

    for _ in 0..<100 {
      if case .waitingForNetwork = sut.downloadPhase { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    if case .waitingForNetwork = sut.downloadPhase {
      XCTAssertTrue(sut.isDownloading)
    } else {
      XCTFail("Expected .waitingForNetwork state, got \(sut.downloadPhase)")
    }
    XCTAssertNotNil(prefs.pendingCAASDownload, "Pending download must be retained on connectivity error")
  }

  func testCancelDownload_cancelsTask_setsCancelledState_andClearsPendingState() {
    let (sut, _, _, _, _, _, _, prefs) = makeSUT()

    sut.startDownload(apiKey: "token123", customerID: "cust123")
    XCTAssertTrue(sut.isDownloading)

    sut.cancelDownload()

    XCTAssertEqual(sut.downloadPhase, .cancelled)
    XCTAssertFalse(sut.isDownloading)
    XCTAssertNil(prefs.pendingCAASDownload, "Pending download must be cleared on cancel")
  }

  func testResumePendingDownloadIfNeeded_resumesUnfinishedDownloadWithPackageID() async throws {
    let downloader = MockChartDownloader()
    let packageService = MockPackageService()
    let downloadID = UUID()
    packageService.packageIDToReturn = downloadID

    let (sut, _, _, _, _, _, _, prefs) = makeSUT(downloader: downloader, packageService: packageService)

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

  func testResumePendingDownloadIfNeeded_resumesUnfinishedDownloadWithoutPackageID() async throws {
    let downloader = MockChartDownloader()
    let packageService = MockPackageService()
    let downloadID = UUID()
    packageService.packageIDToReturn = downloadID

    let (sut, _, _, _, _, _, _, prefs) = makeSUT(downloader: downloader, packageService: packageService)

    let pending = PendingCAASDownload(
      packageID: nil,
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

    let (sut, _, _, _, _, _, _, prefs) = makeSUT(downloadRepository: downloadRepo)

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

  func testDownloadedCharts_andTotalDownloadedSize() {
    let downloadRepo = MockDownloadRepository()
    let download1 = OfflineChartDownload(
      id: UUID(),
      layerID: "shom",
      layerName: "SHOM Brest",
      downloadDate: Date(),
      relativePath: "Charts/brest.mbtiles",
      md5: "hash1",
      zoomMax: 14,
      boundsWKT: "POLYGON(...)",
      customFileSizeBytes: 1000
    )
    let download2 = OfflineChartDownload(
      id: UUID(),
      layerID: "ukho",
      layerName: "UKHO Solent",
      downloadDate: Date(),
      relativePath: "Charts/solent.mbtiles",
      md5: "hash2",
      zoomMax: 14,
      boundsWKT: "POLYGON(...)",
      customFileSizeBytes: 2500
    )
    downloadRepo.downloads = [download1, download2]

    let (sut, _, _, _, _, _, _, _) = makeSUT(downloadRepository: downloadRepo)

    XCTAssertEqual(sut.downloadedCharts.count, 2)
    XCTAssertEqual(sut.downloadedCharts[0].layerName, "SHOM Brest")
    XCTAssertEqual(sut.downloadedCharts[1].layerName, "UKHO Solent")
    XCTAssertEqual(sut.totalDownloadedSize, 3500)
  }

  func testGroupedDownloadedCharts_areSortedAlphabeticallyByTitle() {
    let downloadRepo = MockDownloadRepository()
    let now = Date()

    let ukho = OfflineChartDownload(
      id: UUID(),
      layerID: "ukho",
      layerName: "UKHO",
      downloadDate: now.addingTimeInterval(-100),
      relativePath: "Charts/ukho.mbtiles",
      md5: "hash_ukho",
      zoomMax: 14,
      boundsWKT: "POLYGON(...)",
      customFileSizeBytes: 1000
    )
    let shomRecent = OfflineChartDownload(
      id: UUID(),
      layerID: "shom",
      layerName: "SHOM",
      downloadDate: now,
      relativePath: "Charts/shom2.mbtiles",
      md5: "hash_shom2",
      zoomMax: 14,
      boundsWKT: "POLYGON(...)",
      customFileSizeBytes: 2000
    )
    let shomOld = OfflineChartDownload(
      id: UUID(),
      layerID: "shom",
      layerName: "SHOM",
      downloadDate: now.addingTimeInterval(-200),
      relativePath: "Charts/shom1.mbtiles",
      md5: "hash_shom1",
      zoomMax: 14,
      boundsWKT: "POLYGON(...)",
      customFileSizeBytes: 1500
    )
    let bsh = OfflineChartDownload(
      id: UUID(),
      layerID: "bsh",
      layerName: "BSH Germany",
      downloadDate: now.addingTimeInterval(-50),
      relativePath: "Charts/bsh.mbtiles",
      md5: "hash_bsh",
      zoomMax: 14,
      boundsWKT: "POLYGON(...)",
      customFileSizeBytes: 3000
    )

    downloadRepo.downloads = [ukho, shomRecent, shomOld, bsh]

    let (sut, _, _, _, _, _, _, _) = makeSUT(downloadRepository: downloadRepo)
    let groups = sut.groupedDownloadedCharts

    // Should have 3 groups: BSH Germany, SHOM, UKHO (alphabetical order)
    XCTAssertEqual(groups.count, 3)
    XCTAssertEqual(groups.map(\.title), ["BSH Germany", "SHOM", "UKHO"])

    // SHOM group should have 2 downloads sorted chronologically descending
    let shomGroup = groups.first(where: { $0.layerID == "shom" })
    XCTAssertNotNil(shomGroup)
    XCTAssertEqual(shomGroup?.downloads.count, 2)
    XCTAssertEqual(shomGroup?.downloads.first?.id, shomRecent.id)
    XCTAssertEqual(shomGroup?.downloads.last?.id, shomOld.id)
  }

  func testGroupedDownloadedCharts_usesAvailableLayerBrandNameForSorting() {
    let now = Date()
    let downloads = [
      OfflineChartDownload(
        id: UUID(),
        layerID: "ukho",
        layerName: "UKHO",
        downloadDate: now,
        relativePath: "Charts/ukho.mbtiles",
        md5: "hash1",
        zoomMax: 14,
        boundsWKT: "POLYGON(...)"
      ),
      OfflineChartDownload(
        id: UUID(),
        layerID: "shom",
        layerName: "SHOM",
        downloadDate: now,
        relativePath: "Charts/shom.mbtiles",
        md5: "hash2",
        zoomMax: 14,
        boundsWKT: "POLYGON(...)"
      )
    ]

    let availableLayers = [
      GeoGarageLayer(layer: "ukho", brandName: "Admiralty (UKHO)", versionDate: "2026", validUntil: "2027"),
      GeoGarageLayer(layer: "shom", brandName: "SHOM France", versionDate: "2026", validUntil: "2027")
    ]

    let groups = OfflineChartTypeGroup.group(downloads, availableLayers: availableLayers)

    XCTAssertEqual(groups.count, 2)
    // "Admiralty (UKHO)" comes before "SHOM France" alphabetically
    XCTAssertEqual(groups[0].title, "Admiralty (UKHO)")
    XCTAssertEqual(groups[1].title, "SHOM France")
  }

  func testDeleteDownload_withDownloader_callsDownloader() async throws {
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

    let (sut, _, _, _, _, _, _, _) = makeSUT(downloader: downloader, downloadRepository: downloadRepo)

    try await sut.deleteDownload(download)

    XCTAssertEqual(downloader.deletedIDs.count, 1)
    XCTAssertEqual(downloader.deletedIDs.first, download.id)
  }

  func testDeleteDownload_withoutDownloader_fallsBackToDownloadService() async throws {
    let mockDownloadService = MockGeoGarageDownloadService()
    let downloadRepo = MockDownloadRepository()
    let download = OfflineChartDownload(
      id: UUID(),
      layerID: "shom",
      layerName: "Fallback Chart",
      downloadDate: Date(),
      relativePath: "Charts/fallback.mbtiles",
      md5: "md5hash",
      zoomMax: 14,
      boundsWKT: "POLYGON(...)"
    )
    downloadRepo.downloads = [download]

    let (_, _, _, _, chartVM, _, _, prefs) = makeSUT(
      downloadRepository: downloadRepo,
      customDownloadService: mockDownloadService
    )

    // Construct SUT explicitly without downloader
    let sutWithoutDownloader = OfflineSelectionViewModel(
      downloadService: mockDownloadService,
      downloadRepository: downloadRepo,
      preferencesService: prefs,
      chartViewModel: chartVM,
      offlineMapManager: MockOfflineMapManager(),
      downloader: nil
    )

    try await sutWithoutDownloader.deleteDownload(download)

    XCTAssertEqual(mockDownloadService.deletedDownloads.count, 1)
    XCTAssertEqual(mockDownloadService.deletedDownloads.first?.id, download.id)
  }

  // MARK: - Download Progress Tests

  func testDownloadProgress_acrossVariousPhases() {
    let mockDownloadService = MockGeoGarageDownloadService()
    let (sut, _, _, _, _, _, _, _) = makeSUT(customDownloadService: mockDownloadService)

    // 1. Idle
    mockDownloadService.downloadPhase = .idle
    XCTAssertNil(sut.downloadProgress)
    XCTAssertFalse(sut.isDownloading)

    // 2. Requesting
    mockDownloadService.downloadPhase = .requesting
    XCTAssertNil(sut.downloadProgress)
    XCTAssertTrue(sut.isDownloading)

    // 3. Waiting for network
    mockDownloadService.downloadPhase = .waitingForNetwork(message: "Offline")
    XCTAssertNil(sut.downloadProgress)
    XCTAssertTrue(sut.isDownloading)

    // 4. Generating (determinate)
    mockDownloadService.downloadPhase = .generating(progress: 0.65, message: "Progress: 65%")
    XCTAssertEqual(sut.downloadProgress, 0.65)
    XCTAssertTrue(sut.isDownloading)

    // 5. Generating (indeterminate)
    mockDownloadService.downloadPhase = .generating(progress: nil, message: "Generating...")
    XCTAssertNil(sut.downloadProgress)
    XCTAssertTrue(sut.isDownloading)

    // 6. Downloading (determinate)
    mockDownloadService.downloadPhase = .downloading(receivedBytes: 250, totalBytes: 1000)
    XCTAssertEqual(sut.downloadProgress, 0.25)
    XCTAssertTrue(sut.isDownloading)

    // 7. Downloading (clamping verification)
    mockDownloadService.downloadPhase = .downloading(receivedBytes: 1500, totalBytes: 1000)
    XCTAssertEqual(sut.downloadProgress, 1.0)
    XCTAssertTrue(sut.isDownloading)

    // 8. Downloading (indeterminate / zero total bytes)
    mockDownloadService.downloadPhase = .downloading(receivedBytes: 0, totalBytes: 0)
    XCTAssertNil(sut.downloadProgress)
    XCTAssertTrue(sut.isDownloading)

    // 9. Completed
    let dummyRecord = OfflineChartDownload(
      id: UUID(),
      layerID: "shom",
      layerName: "SHOM",
      downloadDate: Date(),
      relativePath: "Charts/test.mbtiles",
      md5: "abc",
      zoomMax: 14,
      boundsWKT: "POLYGON(...)"
    )
    mockDownloadService.downloadPhase = .completed(dummyRecord)
    XCTAssertNil(sut.downloadProgress)
    XCTAssertFalse(sut.isDownloading)

    // 10. Cancelled
    mockDownloadService.downloadPhase = .cancelled
    XCTAssertNil(sut.downloadProgress)
    XCTAssertFalse(sut.isDownloading)

    // 11. Failed
    mockDownloadService.downloadPhase = .failed(errorMessage: "Failed")
    XCTAssertNil(sut.downloadProgress)
    XCTAssertFalse(sut.isDownloading)
  }
}
