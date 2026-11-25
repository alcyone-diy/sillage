//
//  GeoGarageDownloadPipelineExecutorTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreLocation
import os
import XCTest
@testable import Sillage

@MainActor
final class GeoGarageDownloadPipelineExecutorTests: XCTestCase {

  // MARK: - Strictly Sendable Test Doubles

  private nonisolated enum RecordedAction: Equatable, Sendable {
    case requestPackage(layerID: String)
    case pollStarted(packageID: UUID)
    case downloadStarted(packageID: UUID, localID: UUID?)
    case deleteLocalChart(id: UUID)
    case repositorySave(id: UUID, customName: String?)
    case pipelineEvent(GeoGarageDownloadPipelineEvent)
  }

  private nonisolated final class ActionRecorder: Sendable {
    private let lock = OSAllocatedUnfairLock<[RecordedAction]>(initialState: [])

    func record(_ action: RecordedAction) {
      lock.withLock { $0.append(action) }
    }

    var actions: [RecordedAction] {
      lock.withLock { $0 }
    }
  }

  private nonisolated final class SpyPackageService: GeoGaragePackageServiceProtocol {
    struct State: Sendable {
      var packageIDToReturn = UUID()
      var requestError: CaasError?
      var pollStatuses: [PackageStatusResponse] = []
      var requestCallCount = 0
      var polledPackageIDs: [UUID] = []
    }

    let state = OSAllocatedUnfairLock(initialState: State())
    let recorder: ActionRecorder

    init(recorder: ActionRecorder) {
      self.recorder = recorder
    }

    func requestPackage(_ request: PackageRequest, accessToken: String) async throws(CaasError) -> UUID {
      recorder.record(.requestPackage(layerID: request.layerID))
      let outcome = state.withLock { current -> Result<UUID, CaasError> in
        current.requestCallCount += 1
        if let err = current.requestError {
          return .failure(err)
        }
        return .success(current.packageIDToReturn)
      }
      return try outcome.get()
    }

    func fetchStatus(packageID: UUID, accessToken: String) async throws(CaasError) -> PackageStatusResponse {
      PackageStatusResponse(
        uuid: packageID,
        state: .success,
        tileNumbers: 100,
        tilesPerSec: 10,
        monitor: "100/100",
        eta: nil,
        url: "https://mock.example.com/chart.mbtiles",
        md5: "abc123md5",
        size: 1_048_576,
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
      recorder.record(.pollStarted(packageID: packageID))
      let statuses = state.withLock { current -> [PackageStatusResponse] in
        current.polledPackageIDs.append(packageID)
        return current.pollStatuses
      }

      return AsyncThrowingStream { continuation in
        for status in statuses {
          continuation.yield(status)
        }
        continuation.finish()
      }
    }
  }

  private nonisolated final class SpyChartDownloader: GeoGarageChartDownloaderProtocol {
    struct State: Sendable {
      var downloadError: CaasError?
      var deleteErrorsQueue: [CaasError?] = []
      var progressChunks: [(Int64, Int64)] = []
      var downloadCallCount = 0
      var deletedChartIDs: [UUID] = []
    }

    let state = OSAllocatedUnfairLock(initialState: State())
    let recorder: ActionRecorder

    init(recorder: ActionRecorder) {
      self.recorder = recorder
    }

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
      recorder.record(.downloadStarted(packageID: packageID, localID: localID))
      let (error, chunks) = state.withLock { current -> (CaasError?, [(Int64, Int64)]) in
        current.downloadCallCount += 1
        return (current.downloadError, current.progressChunks)
      }

      if let error {
        throw error
      }

      for (received, total) in chunks {
        progressHandler?(received, total)
      }

      return OfflineChartDownload(
        id: localID ?? packageID,
        layerID: layerID,
        layerName: layerName,
        downloadDate: Date(timeIntervalSince1970: 1_700_000_000),
        relativePath: "GeoGarage/\(layerID).mbtiles",
        md5: expectedMD5,
        zoomMax: zoomMax ?? AppConstants.Cartography.Zoom.defaultOfflineZoomMax,
        boundsWKT: boundsWKT
      )
    }

    func deleteLocalChart(id: UUID) async throws(CaasError) {
      recorder.record(.deleteLocalChart(id: id))
      let maybeError = state.withLock { current -> CaasError? in
        current.deletedChartIDs.append(id)
        if !current.deleteErrorsQueue.isEmpty {
          return current.deleteErrorsQueue.removeFirst()
        }
        return nil
      }
      if let maybeError {
        throw maybeError
      }
    }
  }

  @MainActor
  private final class SpyDownloadRepository: GeoGarageDownloadRepositoryProtocol {
    struct SaveError: Error, LocalizedError {
      var errorDescription: String? { "Simulated SQLite save failure" }
    }

    var downloads: [OfflineChartDownload] = []
    var shouldThrowOnSave = false
    private let recorder: ActionRecorder

    init(recorder: ActionRecorder) {
      self.recorder = recorder
    }

    func load() async {}

    func save(_ download: OfflineChartDownload) async throws {
      recorder.record(.repositorySave(id: download.id, customName: download.customName))
      if shouldThrowOnSave {
        throw SaveError()
      }
      downloads.removeAll { $0.id == download.id }
      downloads.append(download)
    }

    func delete(id: UUID) async throws {
      downloads.removeAll { $0.id == id }
    }

    func lastDownloadDate(for layerID: String) -> Date? { nil }
    func fetchLastDownloadDate(for layerID: String) async throws -> Date? { nil }
  }

  private nonisolated final class StubDiskSpaceProvider: DiskSpaceProviderProtocol {
    let spaceLock: OSAllocatedUnfairLock<Measurement<UnitInformationStorage>?>

    init(availableSpace: Measurement<UnitInformationStorage>?) {
      self.spaceLock = OSAllocatedUnfairLock(initialState: availableSpace)
    }

    func availableDiskSpace() -> Measurement<UnitInformationStorage>? {
      spaceLock.withLock { $0 }
    }
  }

  // MARK: - Helpers

  private var validBrittanyWKT: String {
    GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 47.0, longitude: -3.5),
      northEast: CLLocationCoordinate2D(latitude: 47.5, longitude: -3.0)
    ).toWKT()
  }

  private nonisolated static func makeSuccessStatus(
    packageID: UUID,
    size: Int64? = 2_097_152,
    url: String? = "https://mock.example.com/shom.mbtiles",
    md5: String? = "deadbeef1234"
  ) -> PackageStatusResponse {
    PackageStatusResponse(
      uuid: packageID,
      state: .success,
      tileNumbers: 100,
      tilesPerSec: 25,
      monitor: "100/100",
      eta: nil,
      url: url,
      md5: md5,
      size: size,
      error: nil
    )
  }

  private func makeSUT(
    availableSpace: Measurement<UnitInformationStorage>? = Measurement(value: 10, unit: .gigabytes)
  ) -> (
    sut: GeoGarageDownloadPipelineExecutor,
    packageService: SpyPackageService,
    downloader: SpyChartDownloader,
    repository: SpyDownloadRepository,
    diskSpace: StubDiskSpaceProvider,
    recorder: ActionRecorder
  ) {
    let recorder = ActionRecorder()
    let packageService = SpyPackageService(recorder: recorder)
    let downloader = SpyChartDownloader(recorder: recorder)
    let repository = SpyDownloadRepository(recorder: recorder)
    let diskSpace = StubDiskSpaceProvider(availableSpace: availableSpace)

    let sut = GeoGarageDownloadPipelineExecutor(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: repository,
      diskSpaceProvider: diskSpace
    )
    return (sut, packageService, downloader, repository, diskSpace, recorder)
  }

  // MARK: - 1. Creation vs Resumption

  func testExecute_withoutExistingPackageID_requestsPackagePersistsIDBeforePollingAndDownloads() async throws {
    let (sut, packageService, downloader, _, _, recorder) = makeSUT()
    let assignedPkgID = UUID()
    let localID = UUID()

    packageService.state.withLock {
      $0.packageIDToReturn = assignedPkgID
      $0.pollStatuses = [
        PackageStatusResponse(
          uuid: assignedPkgID,
          state: .started,
          tileNumbers: 100,
          tilesPerSec: 10,
          monitor: nil,
          eta: nil,
          url: nil,
          md5: nil,
          size: nil,
          error: nil
        ),
        Self.makeSuccessStatus(packageID: assignedPkgID, size: 4_096)
      ]
    }
    downloader.state.withLock {
      $0.progressChunks = [(2_048, 4_096), (4_096, 4_096)]
    }

    let progressCollected = OSAllocatedUnfairLock<[(Int64, Int64)]>(initialState: [])
    let item = PendingCAASDownload(
      id: localID,
      packageID: nil,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12
    )

    let record = try await sut.execute(
      item: item,
      accessToken: "valid_token",
      onEvent: { event in
        recorder.record(.pipelineEvent(event))
      },
      onProgress: { received, total in
        progressCollected.withLock { $0.append((received, total)) }
      }
    )

    XCTAssertEqual(record.id, localID)
    XCTAssertEqual(record.md5, "deadbeef1234")
    XCTAssertEqual(progressCollected.withLock { $0 }.count, 2)

    // Verify exact ordering: packageIDAssigned MUST precede pollStarted (survival across OS kill)
    XCTAssertEqual(recorder.actions, [
      .requestPackage(layerID: "shom"),
      .pipelineEvent(.packageIDAssigned(assignedPkgID)),
      .pollStarted(packageID: assignedPkgID),
      .pipelineEvent(.generating(progress: nil, message: "STARTED")),
      .pipelineEvent(.generating(progress: 1.0, message: "SUCCESS: 100/100")),
      .pipelineEvent(.downloadingStarted(totalBytes: 4_096)),
      .downloadStarted(packageID: assignedPkgID, localID: localID)
    ])
  }

  func testExecute_withExistingPackageID_skipsRequestPackageAndPollsDirectly() async throws {
    let (sut, packageService, _, _, _, recorder) = makeSUT()
    let existingPkgID = UUID()
    let localID = UUID()

    packageService.state.withLock {
      $0.pollStatuses = [Self.makeSuccessStatus(packageID: existingPkgID, size: 1_024)]
    }

    let item = PendingCAASDownload(
      id: localID,
      packageID: existingPkgID,
      layerID: "ukho",
      layerName: "UKHO",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12
    )

    let record = try await sut.execute(
      item: item,
      accessToken: "valid_token",
      onEvent: { event in recorder.record(.pipelineEvent(event)) },
      onProgress: { _, _ in }
    )

    XCTAssertEqual(record.id, localID)
    XCTAssertEqual(packageService.state.withLock { $0.requestCallCount }, 0)
    XCTAssertEqual(recorder.actions, [
      .pollStarted(packageID: existingPkgID),
      .pipelineEvent(.generating(progress: 1.0, message: "SUCCESS: 100/100")),
      .pipelineEvent(.downloadingStarted(totalBytes: 1_024)),
      .downloadStarted(packageID: existingPkgID, localID: localID)
    ])
  }

  // MARK: - 2. Polling Validation & Error Propagation

  func testExecute_whenPollFinishesWithoutURLOrMD5_throwsDownloadFailed() async {
    let (sut, packageService, downloader, _, _, _) = makeSUT()
    let pkgID = UUID()

    packageService.state.withLock {
      $0.packageIDToReturn = pkgID
      $0.pollStatuses = [Self.makeSuccessStatus(packageID: pkgID, url: nil, md5: nil)]
    }

    let item = PendingCAASDownload(
      id: UUID(),
      packageID: pkgID,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12
    )

    do {
      _ = try await sut.execute(
        item: item,
        accessToken: "valid_token",
        onEvent: { _ in },
        onProgress: { _, _ in }
      )
      XCTFail("Expected downloadFailed error when URL and MD5 are missing")
    } catch let error as CaasError {
      if case .downloadFailed = error {
        // Expected
      } else {
        XCTFail("Unexpected CaasError case: \(error)")
      }
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }

    XCTAssertEqual(downloader.state.withLock { $0.downloadCallCount }, 0)
  }

  func testExecute_withEmptyAccessToken_throwsAuthenticationRequired() async {
    let (sut, packageService, _, _, _, _) = makeSUT()
    let item = PendingCAASDownload(
      id: UUID(),
      packageID: nil,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12
    )

    do {
      _ = try await sut.execute(
        item: item,
        accessToken: "",
        onEvent: { _ in },
        onProgress: { _, _ in }
      )
      XCTFail("Expected authenticationRequired error")
    } catch let error as CaasError {
      XCTAssertEqual(error, .authenticationRequired)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(packageService.state.withLock { $0.requestCallCount }, 0)
  }

  // MARK: - 3. Cooperative Cancellation

  func testExecute_whenTaskAlreadyCancelled_throwsCancellationErrorWithoutNetworkCalls() async {
    let (sut, packageService, downloader, _, _, recorder) = makeSUT()
    let item = PendingCAASDownload(
      id: UUID(),
      packageID: nil,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12
    )

    let (gateStream, gateContinuation) = AsyncStream<Void>.makeStream()
    let preCancelledTask = Task<OfflineChartDownload, Error> {
      for await _ in gateStream { break }
      return try await sut.execute(
        item: item,
        accessToken: "valid_token",
        onEvent: { event in recorder.record(.pipelineEvent(event)) },
        onProgress: { _, _ in }
      )
    }

    preCancelledTask.cancel()
    gateContinuation.finish()

    do {
      _ = try await preCancelledTask.value
      XCTFail("Expected CancellationError when entering execute on a cancelled task")
    } catch is CancellationError {
      // Expected
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }

    XCTAssertTrue(recorder.actions.isEmpty)
    XCTAssertEqual(packageService.state.withLock { $0.requestCallCount }, 0)
    XCTAssertTrue(packageService.state.withLock { $0.polledPackageIDs.isEmpty })
    XCTAssertEqual(downloader.state.withLock { $0.downloadCallCount }, 0)
  }

  func testExecute_whenCancelledDuringPolling_stopsLoopAndSkipsDownload() async {
    let (sut, packageService, downloader, _, _, recorder) = makeSUT()
    let pkgID = UUID()

    packageService.state.withLock {
      $0.pollStatuses = [
        PackageStatusResponse(
          uuid: pkgID,
          state: .progress,
          tileNumbers: 100,
          tilesPerSec: 10,
          monitor: "25/100",
          eta: nil,
          url: nil,
          md5: nil,
          size: nil,
          error: nil
        ),
        Self.makeSuccessStatus(packageID: pkgID)
      ]
    }

    let item = PendingCAASDownload(
      id: UUID(),
      packageID: pkgID,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12
    )

    let (startGateStream, startGateContinuation) = AsyncStream<Void>.makeStream()
    let taskHolder = OSAllocatedUnfairLock<Task<OfflineChartDownload, Error>?>(initialState: nil)

    let taskCancelledInPoll = Task<OfflineChartDownload, Error> {
      for await _ in startGateStream { break }
      return try await sut.execute(
        item: item,
        accessToken: "valid_token",
        onEvent: { event in
          recorder.record(.pipelineEvent(event))
          if case .generating = event {
            taskHolder.withLock { $0?.cancel() }
          }
        },
        onProgress: { _, _ in }
      )
    }

    taskHolder.withLock { $0 = taskCancelledInPoll }
    startGateContinuation.finish()

    do {
      _ = try await taskCancelledInPoll.value
      XCTFail("Expected CancellationError when cancelled during polling")
    } catch is CancellationError {
      // Expected
    } catch {
      XCTFail("Expected CancellationError, got \(error)")
    }

    XCTAssertEqual(recorder.actions, [
      .pollStarted(packageID: pkgID),
      .pipelineEvent(.generating(progress: 0.25, message: "PROGRESS: 25/100"))
    ])
    XCTAssertEqual(downloader.state.withLock { $0.downloadCallCount }, 0)
  }

  // MARK: - 4. Chart Replacement & OfflineStoragePolicy Semantics

  func testExecute_replacesChartWithSufficientSpace_retainsOldChartUntilDownloadCompletes() async throws {
    let (sut, packageService, downloader, _, _, recorder) = makeSUT(
      availableSpace: Measurement(value: 10, unit: .gigabytes)
    )
    let pkgID = UUID()
    let oldChartID = UUID()
    let newLocalID = UUID()

    packageService.state.withLock {
      $0.packageIDToReturn = pkgID
      $0.pollStatuses = [Self.makeSuccessStatus(packageID: pkgID, size: 5_000_000)]
    }

    let item = PendingCAASDownload(
      id: newLocalID,
      packageID: nil,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12,
      replacesChartID: oldChartID
    )

    _ = try await sut.execute(
      item: item,
      accessToken: "valid_token",
      onEvent: { event in recorder.record(.pipelineEvent(event)) },
      onProgress: { _, _ in }
    )

    // Old chart must ONLY be deleted AFTER downloadStarted, and .replacesChartCleared must NOT be emitted
    XCTAssertFalse(recorder.actions.contains(.pipelineEvent(.replacesChartCleared)))
    let downloadIdx = try XCTUnwrap(recorder.actions.firstIndex(of: .downloadStarted(packageID: pkgID, localID: newLocalID)))
    let deleteIdx = try XCTUnwrap(recorder.actions.firstIndex(of: .deleteLocalChart(id: oldChartID)))
    XCTAssertGreaterThan(deleteIdx, downloadIdx)
    XCTAssertEqual(downloader.state.withLock { $0.deletedChartIDs }, [oldChartID])
  }

  func testExecute_replacesChartWhenDownloadFailsWithSufficientSpace_preservesExistingLocalChart() async {
    let (sut, packageService, downloader, _, _, _) = makeSUT(
      availableSpace: Measurement(value: 10, unit: .gigabytes)
    )
    let pkgID = UUID()
    let oldChartID = UUID()

    packageService.state.withLock {
      $0.packageIDToReturn = pkgID
      $0.pollStatuses = [Self.makeSuccessStatus(packageID: pkgID, size: 5_000_000)]
    }
    downloader.state.withLock {
      $0.downloadError = .md5Mismatch(expected: "aaa", actual: "bbb")
    }

    let item = PendingCAASDownload(
      id: UUID(),
      packageID: pkgID,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12,
      replacesChartID: oldChartID
    )

    do {
      _ = try await sut.execute(
        item: item,
        accessToken: "valid_token",
        onEvent: { _ in },
        onProgress: { _, _ in }
      )
      XCTFail("Expected md5Mismatch error")
    } catch let error as CaasError {
      XCTAssertEqual(error, .md5Mismatch(expected: "aaa", actual: "bbb"))
    } catch {
      XCTFail("Expected CaasError.md5Mismatch, got \(error)")
    }

    XCTAssertTrue(
      downloader.state.withLock { $0.deletedChartIDs.isEmpty },
      "Existing valid chart must never be deleted when new archive validation fails"
    )
  }

  func testExecute_replacesChartWithConstrainedSpaceBeforeRequest_deletesUpfrontAndEmitsCleared() async throws {
    // 100 MB is below OfflineStoragePolicy.minimumDeviceFreeBuffer (300 MB)
    let (sut, packageService, downloader, _, _, recorder) = makeSUT(
      availableSpace: Measurement(value: 100, unit: .megabytes)
    )
    let pkgID = UUID()
    let oldChartID = UUID()

    packageService.state.withLock {
      $0.packageIDToReturn = pkgID
      $0.pollStatuses = [Self.makeSuccessStatus(packageID: pkgID, size: 2_000_000)]
    }

    let item = PendingCAASDownload(
      id: UUID(),
      packageID: nil,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12,
      replacesChartID: oldChartID
    )

    _ = try await sut.execute(
      item: item,
      accessToken: "valid_token",
      onEvent: { event in recorder.record(.pipelineEvent(event)) },
      onProgress: { _, _ in }
    )

    // Deleted once upfront BEFORE requestPackage, .replacesChartCleared emitted immediately, no duplicate post-delete
    let deleteIdx = try XCTUnwrap(recorder.actions.firstIndex(of: .deleteLocalChart(id: oldChartID)))
    let clearedIdx = try XCTUnwrap(recorder.actions.firstIndex(of: .pipelineEvent(.replacesChartCleared)))
    let requestIdx = try XCTUnwrap(recorder.actions.firstIndex(of: .requestPackage(layerID: "shom")))
    XCTAssertLessThan(deleteIdx, clearedIdx)
    XCTAssertLessThan(clearedIdx, requestIdx)
    XCTAssertEqual(downloader.state.withLock { $0.deletedChartIDs }, [oldChartID])
  }

  func testExecute_replacesChartWhenUpfrontDeleteBeforeRequestFails_throwsBlockingError() async {
    let (sut, packageService, downloader, _, _, recorder) = makeSUT(
      availableSpace: Measurement(value: 100, unit: .megabytes)
    )
    let oldChartID = UUID()

    downloader.state.withLock {
      $0.deleteErrorsQueue = [.fileSystemError(underlying: "Permission denied")]
    }

    let item = PendingCAASDownload(
      id: UUID(),
      packageID: nil,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12,
      replacesChartID: oldChartID
    )

    do {
      _ = try await sut.execute(
        item: item,
        accessToken: "valid_token",
        onEvent: { event in recorder.record(.pipelineEvent(event)) },
        onProgress: { _, _ in }
      )
      XCTFail("Expected upfront delete failure before requestPackage to throw")
    } catch let error as CaasError {
      XCTAssertEqual(error, .fileSystemError(underlying: "Permission denied"))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertFalse(recorder.actions.contains(.pipelineEvent(.replacesChartCleared)))
    XCTAssertEqual(packageService.state.withLock { $0.requestCallCount }, 0)
  }

  func testExecute_replacesChartWhenPreDownloadDeleteFails_doesNotClearIDAndRetriesPostDownload() async throws {
    // 500 MB is plenty for small WKT estimate (~3 MB * 1.5 + 300 MB < 500 MB),
    // but insufficient when server reports exact size = 200 MB (200 * 1.5 + 300 = 600 MB > 500 MB).
    let (sut, packageService, downloader, _, _, recorder) = makeSUT(
      availableSpace: Measurement(value: 500, unit: .megabytes)
    )
    let pkgID = UUID()
    let oldChartID = UUID()

    packageService.state.withLock {
      $0.packageIDToReturn = pkgID
      $0.pollStatuses = [Self.makeSuccessStatus(packageID: pkgID, size: 200_000_000)]
    }
    // First delete attempt (pre-download) fails; second attempt (post-download) succeeds
    downloader.state.withLock {
      $0.deleteErrorsQueue = [.fileSystemError(underlying: "Temporary lock"), nil]
    }

    let item = PendingCAASDownload(
      id: UUID(),
      packageID: pkgID,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12,
      replacesChartID: oldChartID
    )

    _ = try await sut.execute(
      item: item,
      accessToken: "valid_token",
      onEvent: { event in recorder.record(.pipelineEvent(event)) },
      onProgress: { _, _ in }
    )

    XCTAssertFalse(
      recorder.actions.contains(.pipelineEvent(.replacesChartCleared)),
      "replacesChartCleared must not be emitted when pre-download delete fails"
    )
    XCTAssertEqual(
      downloader.state.withLock { $0.deletedChartIDs },
      [oldChartID, oldChartID],
      "Post-download cleanup must retry deleting the retained old chart"
    )
  }

  // MARK: - 5. Custom Name & Non-Fatal Final Cleanup

  func testExecute_withCustomNameAndNonFatalPostCleanupErrors_returnsCustomNamedRecordWithoutThrowing() async throws {
    let (sut, packageService, downloader, repository, _, recorder) = makeSUT(
      availableSpace: Measurement(value: 10, unit: .gigabytes)
    )
    let pkgID = UUID()
    let oldChartID = UUID()
    let localID = UUID()

    packageService.state.withLock {
      $0.packageIDToReturn = pkgID
      $0.pollStatuses = [Self.makeSuccessStatus(packageID: pkgID, size: 1_024)]
    }
    repository.shouldThrowOnSave = true
    downloader.state.withLock {
      $0.deleteErrorsQueue = [.fileSystemError(underlying: "Post-cleanup lock")]
    }

    let item = PendingCAASDownload(
      id: localID,
      packageID: pkgID,
      layerID: "shom",
      layerName: "SHOM",
      boundsWKT: validBrittanyWKT,
      zoomMax: 12,
      customName: "Golfe du Morbihan",
      replacesChartID: oldChartID
    )

    let record = try await sut.execute(
      item: item,
      accessToken: "valid_token",
      onEvent: { event in recorder.record(.pipelineEvent(event)) },
      onProgress: { _, _ in }
    )

    XCTAssertEqual(record.id, localID)
    XCTAssertEqual(record.customName, "Golfe du Morbihan")
    XCTAssertTrue(recorder.actions.contains(.repositorySave(id: localID, customName: "Golfe du Morbihan")))
    XCTAssertTrue(recorder.actions.contains(.deleteLocalChart(id: oldChartID)))
  }
}
