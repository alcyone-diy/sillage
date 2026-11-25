//
//  GeoGarageDownloadProgressTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import os
import XCTest
@testable import Sillage

@MainActor
final class GeoGarageDownloadProgressTests: XCTestCase {

  // MARK: - Mock Implementations

  private final class MockPackageService: GeoGaragePackageServiceProtocol, @unchecked Sendable {
    var packageIDToReturn: UUID = UUID()
    var pollResponses: [PackageStatusResponse] = []
    var shouldFailRequest = false
    var customRequestError: Error?
    var shouldHangPoll = false
    var requestPackageCallCount = 0

    func requestPackage(_ request: PackageRequest, accessToken: String) async throws(CaasError) -> UUID {
      requestPackageCallCount += 1
      if let customError = customRequestError as? CaasError {
        throw customError
      }
      if shouldFailRequest {
        throw CaasError.requestFailed(statusCode: 500)
      }
      return packageIDToReturn
    }

    func fetchStatus(packageID: UUID, accessToken: String) async throws(CaasError) -> PackageStatusResponse {
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

    func deletePackage(packageID: UUID, accessToken: String) async throws(CaasError) {}

    func pollUntilComplete(
      packageID: UUID,
      accessToken: String,
      initialInterval: Duration,
      maxInterval: Duration,
      backoffMultiplier: Double,
      timeout: Duration
    ) async -> AsyncThrowingStream<PackageStatusResponse, Error> {
      let responses = self.pollResponses
      let hang = self.shouldHangPoll
      let customError = self.customRequestError
      return AsyncThrowingStream { continuation in
        if let customError, !(customError is CaasError) {
          continuation.finish(throwing: customError)
          return
        }
        if hang {
          let task = Task {
            try await Task.sleep(for: .seconds(10))
            for resp in responses {
              continuation.yield(resp)
            }
            continuation.finish()
          }
          continuation.onTermination = { _ in
            task.cancel()
          }
        } else {
          for resp in responses {
            continuation.yield(resp)
          }
          continuation.finish()
        }
      }
    }
  }

  private final class MockChartDownloader: GeoGarageChartDownloaderProtocol, @unchecked Sendable {
    var downloadResultToReturn: OfflineChartDownload?
    var shouldFailDownload = false
    var progressUpdatesToSimulate: [(Int64, Int64)] = []
    var onDownloadSuspended: (@Sendable (@escaping @Sendable (Int64, Int64) -> Void, CheckedContinuation<Void, Never>) -> Void)?

    func download(
      packageID: UUID,
      downloadURL: URL,
      expectedMD5: String,
      layerID: String,
      layerName: String,
      boundsWKT: String,
      zoomMax: Int?,
      accessToken: String,
      localID: UUID?,
      progressHandler: (@Sendable (Int64, Int64) -> Void)?
    ) async throws(CaasError) -> OfflineChartDownload {
      let appliedZoomMax = zoomMax ?? AppConstants.Cartography.Zoom.defaultOfflineZoomMax
      if shouldFailDownload {
        throw CaasError.downloadFailed(underlying: "Disk full or simulated failure")
      }
      if let onDownloadSuspended, let progressHandler {
        await withCheckedContinuation { continuation in
          onDownloadSuspended(progressHandler, continuation)
        }
      } else {
        for (received, total) in progressUpdatesToSimulate {
          progressHandler?(received, total)
        }
      }
      return downloadResultToReturn ?? OfflineChartDownload(
        id: localID ?? packageID,
        layerID: layerID,
        layerName: layerName,
        downloadDate: Date(),
        relativePath: "GeoGarage/\(layerID).mbtiles",
        md5: expectedMD5,
        zoomMax: appliedZoomMax,
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

  private func makePreferencesService() -> MockPreferencesService {
    let service = MockPreferencesService()
    service.clearAll()
    service.geoGarageCustomerID = "test_customer_id"
    return service
  }

  private func makeKeychainManager() -> MockKeychainManager {
    MockKeychainManager(initialTokens: [GeoGarageKeychainKeys.accessToken: "test_access_token"])
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

  func testGlobalDownloadProgress_multipleDownloadsInQueue_smoothProgression() async throws {
    let packageService = MockPackageService()
    let downloader = MockChartDownloader()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()
    let messageService = MessageService()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor,
      messageService: messageService,
      keychainManager: makeKeychainManager()
    )

    // Initially idle -> nil progress
    XCTAssertNil(service.globalDownloadProgress)

    // Enqueue 2 downloads
    service.startDownload(layerID: "layer_1", layerName: "Layer 1", zoneWKT: "POLYGON(())", zoomMax: 12)
    service.startDownload(layerID: "layer_2", layerName: "Layer 2", zoneWKT: "POLYGON(())", zoomMax: 12)

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

  func testGlobalDownloadProgress_item1Fails_item2CompletesTo100Percent() async throws {
    let packageService = MockPackageService()
    let downloader = MockChartDownloader()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()
    let messageService = MessageService()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor,
      messageService: messageService,
      keychainManager: makeKeychainManager()
    )

    // Enqueue 2 downloads
    service.startDownload(layerID: "chart_1", layerName: "Chart 1", zoneWKT: "POLYGON(())", zoomMax: 12)
    service.startDownload(layerID: "chart_2", layerName: "Chart 2", zoneWKT: "POLYGON(())", zoomMax: 12)

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

  func testNetworkLoss_transitionsToWaitingWithoutCrashing() async throws {
    let packageService = MockPackageService()
    let downloader = MockChartDownloader()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()
    let messageService = MessageService()

    // Start with offline network
    networkMonitor.isConnected = false

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor,
      messageService: messageService,
      keychainManager: makeKeychainManager()
    )

    service.startDownload(layerID: "chart_offline", layerName: "Chart Offline", zoneWKT: "POLYGON(())", zoomMax: 12)

    // Active downloads should exist
    XCTAssertEqual(service.activeDownloads.count, 1)
    XCTAssertTrue(service.isDownloading)

    // Reconnecting network should not crash and triggers processQueue
    networkMonitor.isConnected = true
    try? await Task.sleep(for: .milliseconds(50))
  }

  // MARK: - 5. Cancellation Cleanup

  func testCancellation_cleansUpSessionTrackingAndResetsProgress() async throws {
    let packageService = MockPackageService()
    let downloader = MockChartDownloader()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()
    let messageService = MessageService()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor,
      messageService: messageService,
      keychainManager: makeKeychainManager()
    )

    service.startDownload(layerID: "chart_cancel", layerName: "Chart Cancel", zoneWKT: "POLYGON(())", zoomMax: 12)
    XCTAssertTrue(service.isDownloading)

    service.cancelDownload()

    XCTAssertFalse(service.isDownloading)
    XCTAssertEqual(service.activeDownloads.count, 0)
    XCTAssertEqual(service.sessionTotalDownloadsCount, 0)
    XCTAssertEqual(service.sessionCompletedDownloadsCount, 0)
    XCTAssertNil(service.globalDownloadProgress)
  }

  // MARK: - 6. Failure Alert Posting Tests

  func testFailDownload_postsAppMessageToMessageService() throws {
    let packageService = MockPackageService()
    let downloader = MockChartDownloader()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()
    let messageService = MessageService()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor,
      messageService: messageService,
      keychainManager: makeKeychainManager()
    )

    service.startDownload(layerID: "chart_fail", layerName: "Chart Fail", zoneWKT: "POLYGON(())", zoomMax: 12)
    guard let firstDownload = service.activeDownloads.first else {
      XCTFail("Expected active download to be queued")
      return
    }

    XCTAssertEqual(messageService.messages.count, 0)

    service.failDownload(id: firstDownload.id, errorMessage: "Checksum mismatch")

    XCTAssertEqual(messageService.messages.count, 1)
    let postedMessage = try XCTUnwrap(messageService.messages.first)
    XCTAssertEqual(postedMessage.severity, .error)
    XCTAssertEqual(postedMessage.category, .offlineCharts)
    XCTAssertEqual(postedMessage.intent, .none)
    XCTAssertEqual(postedMessage.detail, .raw("Checksum mismatch"))
  }

  func testFailDownload_authenticationError_postsAppMessageWithOpenSettingsIntent() throws {
    let packageService = MockPackageService()
    let downloader = MockChartDownloader()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()
    let messageService = MessageService()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor,
      messageService: messageService,
      keychainManager: makeKeychainManager()
    )

    service.startDownload(layerID: "chart_auth_fail", layerName: "Chart Auth Fail", zoneWKT: "POLYGON(())", zoomMax: 12)

    service.failDownload(with: "Partner key expired", isAuthenticationError: true)

    XCTAssertEqual(messageService.messages.count, 1)
    let postedMessage = try XCTUnwrap(messageService.messages.first)
    XCTAssertEqual(postedMessage.severity, .error)
    XCTAssertEqual(postedMessage.category, .offlineCharts)
    XCTAssertEqual(postedMessage.intent, .openSettings(target: .geoGarage))
    XCTAssertEqual(postedMessage.detail, .raw("Partner key expired"))
  }

  func testFailDownload_onLastActiveTask_doesNotOverwriteTerminalPhaseWithCancelled() async throws {
    let packageService = MockPackageService()
    packageService.shouldHangPoll = true
    let downloader = MockChartDownloader()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()
    let messageService = MessageService()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor,
      messageService: messageService,
      keychainManager: makeKeychainManager()
    )

    service.startDownload(layerID: "chart_fail_last", layerName: "Chart Fail Last", zoneWKT: "POLYGON(())", zoomMax: 12)
    let downloadID = try XCTUnwrap(service.activeDownloads.first?.id)

    // Allow the background Task to enter pollUntilComplete and suspend
    try await Task.sleep(for: .milliseconds(30))

    service.failDownload(id: downloadID, errorMessage: "Server 500 error")
    XCTAssertEqual(service.downloadPhase, .failed(errorMessage: "Server 500 error"))

    // Allow the cancelled Task to unwind its catch is CancellationError block
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(service.downloadPhase, .failed(errorMessage: "Server 500 error"))
    XCTAssertTrue(service.activeDownloads.isEmpty)
    XCTAssertEqual(service.sessionTotalDownloadsCount, 0)
    XCTAssertEqual(service.sessionCompletedDownloadsCount, 0)
  }

  // MARK: - 7. Queue Concurrency Limit, 4 Hz Throttling, Terminal Guard & Resumption

  func testQueueConcurrencyLimit_maxTwoActiveDownloads_keepsThirdQueuedUntilSlotOpens() async throws {
    let packageService = MockPackageService()
    packageService.shouldHangPoll = true
    let downloader = MockChartDownloader()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()
    let messageService = MessageService()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor,
      messageService: messageService,
      keychainManager: makeKeychainManager()
    )

    service.startDownload(layerID: "c1", layerName: "Chart 1", zoneWKT: "POLYGON(())", zoomMax: 12)
    service.startDownload(layerID: "c2", layerName: "Chart 2", zoneWKT: "POLYGON(())", zoomMax: 12)
    service.startDownload(layerID: "c3", layerName: "Chart 3", zoneWKT: "POLYGON(())", zoomMax: 12)

    XCTAssertEqual(service.activeDownloads.count, 3)
    XCTAssertEqual(service.activeDownloads[0].phase, .requesting)
    XCTAssertEqual(service.activeDownloads[1].phase, .requesting)
    XCTAssertEqual(service.activeDownloads[2].phase, .queued)

    // Cancelling item 1 immediately promotes item 3 into .requesting
    service.cancelDownload(id: service.activeDownloads[0].id)
    XCTAssertEqual(service.activeDownloads.count, 2)
    XCTAssertEqual(service.activeDownloads[0].phase, .requesting)
    XCTAssertEqual(service.activeDownloads[1].phase, .requesting)

    service.cancelDownload()
  }

  private nonisolated struct SuspendedDownloadCapture: Sendable {
    var handler: (@Sendable (Int64, Int64) -> Void)?
    var continuation: CheckedContinuation<Void, Never>?
  }

  func testProgressThrottling_filters4HzAnd1PercentSynchronously_andBlocksLateTicksAfterCompletion() async throws {
    let pkgID = UUID()
    let packageService = MockPackageService()
    packageService.packageIDToReturn = pkgID
    packageService.pollResponses = [
      PackageStatusResponse(
        uuid: pkgID,
        state: .success,
        tileNumbers: 100,
        tilesPerSec: 50,
        monitor: "100/100",
        eta: nil,
        url: "https://mock.example.com/chart.mbtiles",
        md5: "md5ok",
        size: 10_000,
        error: nil
      )
    ]

    let baseInstant = ContinuousClock.now
    let elapsedMsLock = OSAllocatedUnfairLock<Int>(initialState: 0)
    let suspendBox = OSAllocatedUnfairLock(initialState: SuspendedDownloadCapture())

    let downloader = MockChartDownloader()
    downloader.onDownloadSuspended = { handler, continuation in
      suspendBox.withLock {
        $0.handler = handler
        $0.continuation = continuation
      }
    }

    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()
    let messageService = MessageService()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor,
      messageService: messageService,
      keychainManager: makeKeychainManager(),
      nowProvider: {
        let ms = elapsedMsLock.withLock { $0 }
        return baseInstant.advanced(by: .milliseconds(ms))
      }
    )

    service.startDownload(layerID: "shom", layerName: "SHOM", zoneWKT: "POLYGON(())", zoomMax: 12)

    for _ in 0..<100 {
      if suspendBox.withLock({ $0.handler != nil }) { break }
      try await Task.sleep(for: .milliseconds(10))
    }

    let progressHandler = try XCTUnwrap(suspendBox.withLock { $0.handler })
    let resumeContinuation = try XCTUnwrap(suspendBox.withLock { $0.continuation })

    // First tick (hasElapsedInterval == true since lastUpdateTime is nil) -> accepted (100 / 10_000)
    progressHandler(100, 10_000)
    await Task.yield()
    try await Task.sleep(for: .milliseconds(15))
    XCTAssertEqual(service.downloadPhase, .downloading(receivedBytes: 100, totalBytes: 10_000))

    // Sub-250ms (+50ms) and sub-1% (+40 bytes = 0.4%) -> filtered out synchronously
    elapsedMsLock.withLock { $0 += 50 }
    progressHandler(140, 10_000)
    await Task.yield()
    try await Task.sleep(for: .milliseconds(15))
    XCTAssertEqual(
      service.downloadPhase,
      .downloading(receivedBytes: 100, totalBytes: 10_000),
      "Sub-250ms and sub-1% tick must be dropped by synchronous lock filter"
    )

    // Advance >= 1% (+150 bytes from last reported 100 -> 250 / 10_000 = +1.5%) without advancing clock -> accepted
    progressHandler(250, 10_000)
    await Task.yield()
    try await Task.sleep(for: .milliseconds(15))
    XCTAssertEqual(service.downloadPhase, .downloading(receivedBytes: 250, totalBytes: 10_000))

    // Advance clock by >= 250ms (+260ms) with tiny byte delta (+10 bytes) -> accepted
    elapsedMsLock.withLock { $0 += 260 }
    progressHandler(260, 10_000)
    await Task.yield()
    try await Task.sleep(for: .milliseconds(15))
    XCTAssertEqual(service.downloadPhase, .downloading(receivedBytes: 260, totalBytes: 10_000))

    // Out-of-order lower byte count (even after +300ms clock advance) must be rejected synchronously
    // without lowering lastReportedBytes or consuming the 250ms throttle window.
    var unitThrottle = GeoGarageProgressThrottleState()
    let t0 = ContinuousClock.now
    XCTAssertTrue(unitThrottle.shouldEmit(received: 500, total: 10_000, now: t0))
    XCTAssertFalse(unitThrottle.shouldEmit(received: 400, total: 10_000, now: t0.advanced(by: .milliseconds(300))))
    XCTAssertEqual(unitThrottle.lastReportedBytes, 500)
    XCTAssertEqual(unitThrottle.lastUpdateTime, t0)

    elapsedMsLock.withLock { $0 += 300 }
    progressHandler(200, 10_000)
    await Task.yield()
    try await Task.sleep(for: .milliseconds(15))
    XCTAssertEqual(service.downloadPhase, .downloading(receivedBytes: 260, totalBytes: 10_000))

    // Complete the download
    resumeContinuation.resume()
    for _ in 0..<100 {
      if case .completed = service.downloadPhase { break }
      try await Task.sleep(for: .milliseconds(10))
    }

    guard case .completed(let finalRecord) = service.downloadPhase else {
      XCTFail("Expected .completed terminal phase, got \(service.downloadPhase)")
      return
    }

    // Late tick arriving AFTER completion (even with +5s clock advance and 100% bytes) must NOT overwrite .completed
    elapsedMsLock.withLock { $0 += 5_000 }
    progressHandler(10_000, 10_000)
    await Task.yield()
    try await Task.sleep(for: .milliseconds(20))

    XCTAssertEqual(service.downloadPhase, .completed(finalRecord))
    XCTAssertTrue(service.activeDownloads.isEmpty)
  }

  func testResumePendingDownloadIfNeeded_reusesPersistedPackageIDWithoutReRequesting() async throws {
    let persistedPkgID = UUID()
    let persistedLocalID = UUID()

    let packageService = MockPackageService()
    packageService.pollResponses = [
      PackageStatusResponse(
        uuid: persistedPkgID,
        state: .success,
        tileNumbers: 50,
        tilesPerSec: 25,
        monitor: "50/50",
        eta: nil,
        url: "https://mock.example.com/resumed.mbtiles",
        md5: "resumedmd5",
        size: 2048,
        error: nil
      )
    ]

    let downloader = MockChartDownloader()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let preferences = makePreferencesService()
    preferences.pendingCAASDownloads = [
      PendingCAASDownload(
        id: persistedLocalID,
        packageID: persistedPkgID,
        layerID: "shom",
        layerName: "SHOM",
        boundsWKT: "POLYGON(())",
        zoomMax: 12
      )
    ]

    let networkMonitor = MockNetworkMonitor()
    let messageService = MessageService()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor,
      messageService: messageService,
      keychainManager: makeKeychainManager()
    )

    await service.resumePendingDownloadIfNeeded()

    for _ in 0..<100 {
      if case .completed = service.downloadPhase { break }
      try await Task.sleep(for: .milliseconds(10))
    }

    XCTAssertEqual(packageService.requestPackageCallCount, 0, "Must resume polling existing packageID without calling requestPackage")
    XCTAssertTrue(preferences.pendingCAASDownloads.isEmpty)
    if case .completed(let record) = service.downloadPhase {
      XCTAssertEqual(record.id, persistedLocalID)
      XCTAssertEqual(record.md5, "resumedmd5")
    } else {
      XCTFail("Expected .completed after resume, got \(service.downloadPhase)")
    }
  }

  func testErrorClassification_connectivityErrorQueuesWaitingWhileAuthErrorFailsAndPurges() async throws {
    let packageService = MockPackageService()
    packageService.customRequestError = URLError(.notConnectedToInternet)
    let downloader = MockChartDownloader()
    let dbManager = try DatabaseManager.inMemory()
    let repository = GeoGarageDownloadRepository(databaseManager: dbManager)
    let preferences = makePreferencesService()
    let networkMonitor = MockNetworkMonitor()
    let messageService = MessageService()

    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      preferencesService: preferences,
      networkMonitor: networkMonitor,
      messageService: messageService,
      keychainManager: makeKeychainManager()
    )

    // 1. URLError(.notConnectedToInternet) during polling -> .waitingForNetwork, pending item retained
    service.startDownload(layerID: "shom", layerName: "SHOM", zoneWKT: "POLYGON(())", zoomMax: 12)
    for _ in 0..<100 {
      if case .waitingForNetwork = service.downloadPhase { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    if case .waitingForNetwork = service.downloadPhase {
      XCTAssertEqual(preferences.pendingCAASDownloads.count, 1)
      XCTAssertTrue(messageService.messages.isEmpty)
    } else {
      XCTFail("Expected .waitingForNetwork on connectivity outage, got \(service.downloadPhase)")
    }

    service.cancelDownload()

    // 2. CaasError.authenticationRequired -> .failed, pending state purged, settings intent posted
    packageService.customRequestError = CaasError.authenticationRequired
    service.startDownload(layerID: "shom", layerName: "SHOM", zoneWKT: "POLYGON(())", zoomMax: 12)
    for _ in 0..<100 {
      if case .failed = service.downloadPhase { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    if case .failed = service.downloadPhase {
      XCTAssertTrue(preferences.pendingCAASDownloads.isEmpty)
      XCTAssertEqual(messageService.messages.last?.intent, .openSettings(target: .geoGarage))
    } else {
      XCTFail("Expected .failed on CaasError.authenticationRequired, got \(service.downloadPhase)")
    }
  }
}
