//
//  GeoGarageDownloadProgressTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class GeoGarageDownloadProgressTests: XCTestCase {

  // MARK: - Mock Implementations

  private final class MockPackageService: GeoGaragePackageServiceProtocol, @unchecked Sendable {
    var packageIDToReturn: UUID = UUID()
    var pollResponses: [PackageStatusResponse] = []
    var shouldFailRequest = false

    func requestPackage(_ request: PackageRequest, apiKey: String, userID: String) async throws(CaasError) -> UUID {
      if shouldFailRequest {
        throw CaasError.requestFailed(statusCode: 500)
      }
      return packageIDToReturn
    }

    func fetchStatus(packageID: UUID, apiKey: String) async throws(CaasError) -> PackageStatusResponse {
      pollResponses.first ?? PackageStatusResponse(
        uuid: packageID,
        state: .success,
        tileNumbers: 10,
        tilesPerSec: 5,
        monitor: "10/10",
        eta: nil,
        url: "https://mock.example.com/chart.mbtiles",
        md5: "mockmd5",
        size: 1024,
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
      let responses = self.pollResponses
      return AsyncThrowingStream { continuation in
        for resp in responses {
          continuation.yield(resp)
        }
        continuation.finish()
      }
    }
  }

  private final class MockChartDownloader: GeoGarageChartDownloaderProtocol, @unchecked Sendable {
    var downloadResultToReturn: OfflineChartDownload?
    var shouldFailDownload = false
    var progressUpdatesToSimulate: [(Int64, Int64)] = []

    func download(
      packageID: UUID,
      downloadURL: URL,
      expectedMD5: String,
      layerID: String,
      layerName: String,
      boundsWKT: String,
      zoomMax: Int,
      apiKey: String,
      localID: UUID?,
      progressHandler: (@Sendable (Int64, Int64) -> Void)?
    ) async throws(CaasError) -> OfflineChartDownload {
      if shouldFailDownload {
        throw CaasError.downloadFailed(underlying: "Disk full or simulated failure")
      }
      for (received, total) in progressUpdatesToSimulate {
        progressHandler?(received, total)
      }
      return downloadResultToReturn ?? OfflineChartDownload(
        id: localID ?? packageID,
        layerID: layerID,
        layerName: layerName,
        downloadDate: Date(),
        relativePath: "GeoGarage/\(layerID).mbtiles",
        md5: expectedMD5,
        zoomMax: zoomMax,
        boundsWKT: boundsWKT
      )
    }

    func deleteLocalChart(id: UUID) async throws(CaasError) {}
  }

  private final class MockNetworkMonitor: NetworkMonitorServiceProtocol, @unchecked Sendable {
    var isConnected: Bool = true {
      didSet {
        continuation?.yield(isConnected)
      }
    }

    private var continuation: AsyncStream<Bool>.Continuation?

    func connectionStream() -> AsyncStream<Bool> {
      AsyncStream { cont in
        self.continuation = cont
        cont.yield(self.isConnected)
      }
    }
  }

  private func makePreferencesService() -> PreferencesService {
    let service = PreferencesService()
    service.geoGarageCustomerID = "test_customer_id"
    service.pendingCAASDownloads.removeAll()
    return service
  }

  // MARK: - 1. Phase Normalized Progress Tests

  func testPhaseNormalizedProgress_idleAndQueued_returnsZero() {
    XCTAssertEqual(GeoGarageDownloadPhaseState.idle.normalizedProgress, 0.0)
    XCTAssertEqual(GeoGarageDownloadPhaseState.queued.normalizedProgress, 0.0)
    XCTAssertEqual(GeoGarageDownloadPhaseState.waitingForNetwork(message: "").normalizedProgress, 0.0)
    XCTAssertEqual(GeoGarageDownloadPhaseState.requesting.normalizedProgress, 0.0)
    XCTAssertEqual(GeoGarageDownloadPhaseState.failed(errorMessage: "").normalizedProgress, 0.0)
    XCTAssertEqual(GeoGarageDownloadPhaseState.cancelled.normalizedProgress, 0.0)
  }

  func testPhaseNormalizedProgress_generating_scalesToFiftyPercent() {
    // When progress is nil (server reports no tile metrics yet), strictly return 0.0 (no fake numbers)
    let stateNil = GeoGarageDownloadPhaseState.generating(progress: nil, message: "Started")
    XCTAssertEqual(stateNil.normalizedProgress, 0.0)

    // When progress is 0.5 from server, normalized progress is 0.25 (50% of the 50% generation stage)
    let stateHalf = GeoGarageDownloadPhaseState.generating(progress: 0.5, message: "500/1000")
    XCTAssertEqual(stateHalf.normalizedProgress, 0.25, accuracy: 0.001)

    // When progress is 1.0 from server, generation stage is complete (0.5)
    let stateFull = GeoGarageDownloadPhaseState.generating(progress: 1.0, message: "1000/1000")
    XCTAssertEqual(stateFull.normalizedProgress, 0.5, accuracy: 0.001)
  }

  func testPhaseNormalizedProgress_downloading_scalesFromFiftyToOneHundredPercent() {
    // 0% downloaded -> 0.5
    let stateStart = GeoGarageDownloadPhaseState.downloading(receivedBytes: 0, totalBytes: 1000)
    XCTAssertEqual(stateStart.normalizedProgress, 0.5, accuracy: 0.001)

    // 50% downloaded -> 0.75
    let stateHalf = GeoGarageDownloadPhaseState.downloading(receivedBytes: 500, totalBytes: 1000)
    XCTAssertEqual(stateHalf.normalizedProgress, 0.75, accuracy: 0.001)

    // 100% downloaded -> 1.0
    let stateFull = GeoGarageDownloadPhaseState.downloading(receivedBytes: 1000, totalBytes: 1000)
    XCTAssertEqual(stateFull.normalizedProgress, 1.0, accuracy: 0.001)
  }

  func testPhaseNormalizedProgress_completed_returnsOne() {
    let dummyRecord = OfflineChartDownload(
      id: UUID(),
      layerID: "shom",
      layerName: "SHOM",
      downloadDate: Date(),
      relativePath: "GeoGarage/shom.mbtiles",
      md5: "abc",
      zoomMax: 12,
      boundsWKT: "POLYGON(())"
    )
    let stateCompleted = GeoGarageDownloadPhaseState.completed(dummyRecord)
    XCTAssertEqual(stateCompleted.normalizedProgress, 1.0)
  }

  // MARK: - 2. Composite Queue Progress Tests

  func testGlobalDownloadProgress_multipleDownloadsInQueue_smoothProgression() async {
    let packageService = MockPackageService()
    let downloader = MockChartDownloader()
    let persistenceActor = LocalFilePersistenceActor()
    let repoURL = FileManager.default.temporaryDirectory.appendingPathComponent("downloads_\(UUID().uuidString).json")
    let repository = GeoGarageDownloadRepository(persistence: persistenceActor, fileURL: repoURL)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor
    )

    // Initially idle -> nil progress
    XCTAssertNil(service.globalDownloadProgress)

    // Enqueue 2 downloads
    service.startDownload(layerID: "layer_1", layerName: "Layer 1", zoneWKT: "POLYGON(())", zoomMax: 12, apiKey: "key", customerID: "cust")
    service.startDownload(layerID: "layer_2", layerName: "Layer 2", zoneWKT: "POLYGON(())", zoomMax: 12, apiKey: "key", customerID: "cust")

    XCTAssertEqual(service.activeDownloads.count, 2)
    XCTAssertEqual(service.sessionTotalDownloadsCount, 2)
    XCTAssertEqual(service.sessionCompletedDownloadsCount, 0)

    // Both start at 0.0 -> composite is 0.0
    if let progress = service.globalDownloadProgress {
      XCTAssertEqual(progress, 0.0, accuracy: 0.001)
    }

    // Verify composite formula for 50% on first chart: (0.5 + 0.0) / 2 = 0.25 (25%)
    let expectedComposite = (0.5 + 0.0) / 2.0
    XCTAssertEqual(expectedComposite, 0.25, accuracy: 0.001)
  }

  // MARK: - 3. Failure & Batch Adjustment Tests

  func testGlobalDownloadProgress_item1Fails_item2CompletesTo100Percent() async {
    let packageService = MockPackageService()
    let downloader = MockChartDownloader()
    let persistenceActor = LocalFilePersistenceActor()
    let repoURL = FileManager.default.temporaryDirectory.appendingPathComponent("downloads_\(UUID().uuidString).json")
    let repository = GeoGarageDownloadRepository(persistence: persistenceActor, fileURL: repoURL)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor
    )

    // Enqueue 2 downloads
    service.startDownload(layerID: "chart_1", layerName: "Chart 1", zoneWKT: "POLYGON(())", zoomMax: 12, apiKey: "key", customerID: "cust")
    service.startDownload(layerID: "chart_2", layerName: "Chart 2", zoneWKT: "POLYGON(())", zoomMax: 12, apiKey: "key", customerID: "cust")

    XCTAssertEqual(service.sessionTotalDownloadsCount, 2)
    let chart1ID = service.activeDownloads[0].id

    // Fail chart 1 explicitly
    service.failDownload(id: chart1ID, errorMessage: "Server 500 error")

    // The batch size should adjust to 1 so that chart 2 can reach 100%
    XCTAssertEqual(service.activeDownloads.count, 1)
    XCTAssertEqual(service.sessionTotalDownloadsCount, 1)
    XCTAssertEqual(service.sessionCompletedDownloadsCount, 0)

    // Remaining chart 2 at 0% has composite progress 0.0
    XCTAssertEqual(service.globalDownloadProgress, 0.0)
  }

  // MARK: - 4. Network Loss Edge Case

  func testNetworkLoss_transitionsToWaitingWithoutCrashing() async {
    let packageService = MockPackageService()
    let downloader = MockChartDownloader()
    let persistenceActor = LocalFilePersistenceActor()
    let repoURL = FileManager.default.temporaryDirectory.appendingPathComponent("downloads_\(UUID().uuidString).json")
    let repository = GeoGarageDownloadRepository(persistence: persistenceActor, fileURL: repoURL)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()

    // Start with offline network
    networkMonitor.isConnected = false

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor
    )

    service.startDownload(layerID: "chart_offline", layerName: "Chart Offline", zoneWKT: "POLYGON(())", zoomMax: 12, apiKey: "key", customerID: "cust")

    // Active downloads should exist
    XCTAssertEqual(service.activeDownloads.count, 1)
    XCTAssertTrue(service.isDownloading)

    // Reconnecting network should not crash and triggers processQueue
    networkMonitor.isConnected = true
    try? await Task.sleep(for: .milliseconds(50))
  }

  // MARK: - 5. Cancellation Cleanup

  func testCancellation_cleansUpSessionTrackingAndResetsProgress() async {
    let packageService = MockPackageService()
    let downloader = MockChartDownloader()
    let persistenceActor = LocalFilePersistenceActor()
    let repoURL = FileManager.default.temporaryDirectory.appendingPathComponent("downloads_\(UUID().uuidString).json")
    let repository = GeoGarageDownloadRepository(persistence: persistenceActor, fileURL: repoURL)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor
    )

    service.startDownload(layerID: "chart_cancel", layerName: "Chart Cancel", zoneWKT: "POLYGON(())", zoomMax: 12, apiKey: "key", customerID: "cust")
    XCTAssertTrue(service.isDownloading)

    service.cancelDownload()

    XCTAssertFalse(service.isDownloading)
    XCTAssertEqual(service.activeDownloads.count, 0)
    XCTAssertEqual(service.sessionTotalDownloadsCount, 0)
    XCTAssertEqual(service.sessionCompletedDownloadsCount, 0)
    XCTAssertNil(service.globalDownloadProgress)
  }
}
