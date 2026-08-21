//
//  GeoGarageDownloadService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

/// A global, persistent service responsible for orchestrating GeoGarage CAAS chart package
/// generation, polling, downloading, state preservation across app terminations, and automatic
/// recovery upon network reconnection.
///
/// ### Architectural Rationale:
/// 1. **ViewModel Decoupling:**
///    Downloading a chart package is a long-lived operation that may take minutes over cellular/satellite connections.
///    Placing the execution pipeline inside `OfflineSelectionViewModel` caused downloads and recovery to be cancelled
///    whenever the selection panel was dismissed by the user. By isolating the pipeline in this persistent service
///    instantiated within `AppEnvironment`, downloads proceed uninterrupted regardless of active view lifecycles.
///
/// 2. **Structured Concurrency Network Observation:**
///    Instead of legacy `NotificationCenter` broadcasts, this service consumes `NetworkMonitorService.connectionStream()`,
///    an `AsyncStream<Bool>`, within an isolated `Task` loop with cooperative cancellation. When connectivity transitions
///    to `true`, pending downloads are seamlessly resumed.
///
/// 3. **Synchronous State Persistence Before Network Dispatch:**
///    To guarantee resilience against immediate app crashes or sudden terminations, `PendingCAASDownload` is written
///    synchronously to `PreferencesService` (UserDefaults) with `packageID = nil` *before* the first HTTP request is dispatched.
///
/// 4. **Fine-Grained Local Connectivity Error Classification:**
///    Only true local connectivity outages (e.g. `URLError.notConnectedToInternet`, `URLError.networkConnectionLost`,
///    `URLError.dataNotAllowed`) transition the workflow into `.waitingForNetwork` while keeping the request queued.
///    Fatal errors (HTTP 401 Unauthorized, HTTP 400 Bad Request, server generation failures, MD5 corruption) are routed
///    to `.failed(errorMessage:)` and purge the pending state to prevent infinite retry loops and excessive battery drain.
///
/// 5. **Cooperative Cancellation:**
///    The active download task is tracked via `currentDownloadTask`. Cooperative cancellation checks (`Task.checkCancellation()`)
///    are performed between each pipeline phase (request, polling steps, download) to ensure clean deallocation.
@Observable
@MainActor
final class GeoGarageDownloadService: GeoGarageDownloadServiceProtocol, @unchecked Sendable {

  // MARK: - Injected Dependencies

  private let packageService: GeoGaragePackageServiceProtocol
  private let downloader: GeoGarageChartDownloaderProtocol
  private let downloadRepository: GeoGarageDownloadRepositoryProtocol
  private let preferencesService: PreferencesServiceProtocol
  private let networkMonitor: NetworkMonitorServiceProtocol

  // MARK: - State Properties

  private(set) var downloadPhase: GeoGarageDownloadPhaseState = .idle

  @ObservationIgnored
  private var currentDownloadTask: Task<Void, Never>?

  @ObservationIgnored
  private var networkObservationTask: Task<Void, Never>?

  // MARK: - Computed Properties

  var isDownloading: Bool {
    switch downloadPhase {
    case .waitingForNetwork, .requesting, .generating, .downloading:
      return true
    case .idle, .completed, .failed, .cancelled:
      return false
    }
  }

  /// Normalized progress value strictly between 0.0 and 1.0 when available, or nil for indeterminate state.
  var downloadProgress: Double? {
    switch downloadPhase {
    case .generating(let progress, _):
      guard let progress else { return nil }
      return min(max(progress, 0.0), 1.0)
    case .downloading(let receivedBytes, let totalBytes):
      guard totalBytes > 0 else { return nil }
      let ratio = Double(receivedBytes) / Double(totalBytes)
      return min(max(ratio, 0.0), 1.0)
    case .idle, .waitingForNetwork, .requesting, .completed, .failed, .cancelled:
      return nil
    }
  }

  // MARK: - Initializer

  init(
    packageService: GeoGaragePackageServiceProtocol,
    downloader: GeoGarageChartDownloaderProtocol,
    downloadRepository: GeoGarageDownloadRepositoryProtocol,
    preferencesService: PreferencesServiceProtocol,
    networkMonitor: NetworkMonitorServiceProtocol
  ) {
    self.packageService = packageService
    self.downloader = downloader
    self.downloadRepository = downloadRepository
    self.preferencesService = preferencesService
    self.networkMonitor = networkMonitor

    // Technical Design: Listen to modern AsyncStream from NetworkMonitorService to auto-resume queued requests
    self.networkObservationTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      for await isConnected in self.networkMonitor.connectionStream() {
        guard !Task.isCancelled else { break }
        if isConnected {
          await self.resumePendingDownloadIfNeeded()
        }
      }
    }
  }

  deinit {
    networkObservationTask?.cancel()
    currentDownloadTask?.cancel()
  }

  // MARK: - Public API

  func startDownload(
    layerID: String,
    layerName: String,
    zoneWKT: String,
    zoomMax: Int,
    apiKey: String,
    customerID: String
  ) {
    guard !isDownloading else { return }

    // Technical Design: Immediate synchronous persistence to survive crashes before network execution starts
    let pending = PendingCAASDownload(
      packageID: nil,
      layerID: layerID,
      layerName: layerName,
      boundsWKT: zoneWKT,
      zoomMax: zoomMax,
      createdAt: Date()
    )
    preferencesService.pendingCAASDownload = pending
    downloadPhase = .requesting

    currentDownloadTask?.cancel()
    currentDownloadTask = Task { [weak self] in
      guard let self = self else { return }
      await self.executeDownloadPipeline(
        apiKey: apiKey,
        customerID: customerID,
        layerID: layerID,
        layerName: layerName,
        zoneWKT: zoneWKT,
        zoomMax: zoomMax,
        existingPackageID: nil
      )
    }
  }

  func resumePendingDownloadIfNeeded() async {
    guard let pending = preferencesService.pendingCAASDownload else { return }

    // If package was already completely downloaded and registered, purge pending state
    if let pkgID = pending.packageID, downloadRepository.downloads.contains(where: { $0.id == pkgID }) {
      Logger.offline.info("Pending download \(pkgID.uuidString, privacy: .public) already completed in repository. Clearing pending state.")
      preferencesService.pendingCAASDownload = nil
      downloadPhase = .idle
      return
    }

    guard let customerID = preferencesService.geoGarageCustomerID, !customerID.isEmpty else {
      Logger.offline.warning("Cannot resume pending download: missing customer ID.")
      preferencesService.pendingCAASDownload = nil
      downloadPhase = .failed(errorMessage: String(localized: "User is not authenticated with GeoGarage. Please login first."))
      return
    }

    let caasKey = AppConfiguration.shared.geoGarageCaasApiKey
    let token = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token") ?? ""
    let apiKey = (!caasKey.isEmpty && caasKey != "test_caas_api_key") ? caasKey : token

    guard !apiKey.isEmpty else {
      Logger.offline.warning("Cannot resume pending download: missing API key.")
      preferencesService.pendingCAASDownload = nil
      downloadPhase = .failed(errorMessage: CaasError.authenticationRequired.localizedDescription)
      return
    }

    if isDownloading {
      if case .waitingForNetwork = downloadPhase {
        // Proceed to resume from offline waiting state
      } else {
        return
      }
    }

    Logger.offline.info("Resuming pending CAAS download for layer '\(pending.layerID, privacy: .public)' (packageID: \(pending.packageID?.uuidString ?? "nil", privacy: .public))")
    downloadPhase = .requesting

    currentDownloadTask?.cancel()
    currentDownloadTask = Task { [weak self] in
      guard let self = self else { return }
      await self.executeDownloadPipeline(
        apiKey: apiKey,
        customerID: customerID,
        layerID: pending.layerID,
        layerName: pending.layerName,
        zoneWKT: pending.boundsWKT,
        zoomMax: pending.zoomMax,
        existingPackageID: pending.packageID
      )
    }
  }

  func cancelDownload() {
    Logger.offline.info("GeoGarageDownloadService: cancelDownload called by user")
    currentDownloadTask?.cancel()
    currentDownloadTask = nil
    downloadPhase = .cancelled
    preferencesService.pendingCAASDownload = nil
  }

  func failDownload(with errorMessage: String) {
    Logger.offline.error("GeoGarageDownloadService: download failed explicitly: \(errorMessage, privacy: .public)")
    currentDownloadTask?.cancel()
    currentDownloadTask = nil
    downloadPhase = .failed(errorMessage: errorMessage)
    preferencesService.pendingCAASDownload = nil
  }

  func deleteDownload(_ download: OfflineChartDownload) async throws(CaasError) {
    try await downloader.deleteLocalChart(id: download.id)
  }

  // MARK: - Pipeline Execution

  private func executeDownloadPipeline(
    apiKey: String,
    customerID: String,
    layerID: String,
    layerName: String,
    zoneWKT: String,
    zoomMax: Int,
    existingPackageID: UUID?
  ) async {
    guard !Task.isCancelled else {
      downloadPhase = .cancelled
      preferencesService.pendingCAASDownload = nil
      return
    }

    guard !apiKey.isEmpty else {
      downloadPhase = .failed(errorMessage: CaasError.authenticationRequired.localizedDescription)
      preferencesService.pendingCAASDownload = nil
      return
    }

    // Check reachability before initiating network requests
    guard networkMonitor.isConnected else {
      Logger.offline.info("Device is offline. Queuing pending CAAS download for '\(layerID, privacy: .public)' until connection is restored.")
      downloadPhase = .waitingForNetwork(message: String(localized: "Waiting for network connection…"))
      return
    }

    do {
      try Task.checkCancellation()

      let packageID: UUID
      if let existing = existingPackageID {
        packageID = existing
      } else {
        let request = PackageRequest(
          layerID: layerID,
          zoneWKT: zoneWKT,
          zoomMax: zoomMax,
          format: .mbtiles,
          cipher: .v4
        )

        packageID = try await packageService.requestPackage(
          request,
          apiKey: apiKey,
          userID: customerID
        )

        try Task.checkCancellation()

        // Persist the assigned packageID immediately after server acknowledges creation
        let updatedPending = PendingCAASDownload(
          packageID: packageID,
          layerID: layerID,
          layerName: layerName,
          boundsWKT: zoneWKT,
          zoomMax: zoomMax,
          createdAt: Date()
        )
        preferencesService.pendingCAASDownload = updatedPending
      }

      try Task.checkCancellation()

      try await pollAndDownloadArchive(
        packageID: packageID,
        apiKey: apiKey,
        layerID: layerID,
        layerName: layerName,
        boundsWKT: zoneWKT,
        zoomMax: zoomMax
      )
    } catch is CancellationError {
      downloadPhase = .cancelled
      preferencesService.pendingCAASDownload = nil
    } catch {
      if isConnectivityError(error) {
        Logger.offline.info("Network connectivity error during CAAS download: \(error.localizedDescription, privacy: .public). Queued in pending state.")
        downloadPhase = .waitingForNetwork(message: String(localized: "Waiting for network connection…"))
      } else {
        Logger.offline.error("Fatal error during CAAS download: \(error.localizedDescription, privacy: .public)")
        downloadPhase = .failed(errorMessage: error.localizedDescription)
        preferencesService.pendingCAASDownload = nil
      }
    }
  }

  private func pollAndDownloadArchive(
    packageID: UUID,
    apiKey: String,
    layerID: String,
    layerName: String,
    boundsWKT: String,
    zoomMax: Int
  ) async throws {
    var finalStatus: PackageStatusResponse?

    let statusStream = await packageService.pollUntilComplete(
      packageID: packageID,
      apiKey: apiKey
    )

    for try await status in statusStream {
      try Task.checkCancellation()

      let progress = status.normalizedProgress
      let msg: String
      if let monitor = status.monitor {
        msg = "\(status.state.rawValue): \(monitor)"
      } else {
        msg = status.state.rawValue
      }
      downloadPhase = .generating(progress: progress, message: msg)

      if status.state == .success {
        finalStatus = status
      }
    }

    try Task.checkCancellation()

    guard let completedStatus = finalStatus,
          let rawURLString = completedStatus.url,
          let downloadURL = URL(string: rawURLString),
          let fileHash = completedStatus.md5 else {
      throw CaasError.downloadFailed(underlying: "Server generation completed without valid download URL or MD5 hash.")
    }

    let totalBytes = completedStatus.size ?? 0
    downloadPhase = .downloading(receivedBytes: 0, totalBytes: totalBytes)

    let record = try await downloader.download(
      packageID: packageID,
      downloadURL: downloadURL,
      expectedMD5: fileHash,
      layerID: layerID,
      layerName: layerName,
      boundsWKT: boundsWKT,
      zoomMax: zoomMax,
      apiKey: apiKey
    )

    downloadPhase = .completed(record)
    preferencesService.pendingCAASDownload = nil
  }

  // MARK: - Error Classification Helper

  /// Determines whether an error corresponds to a local network disconnection
  /// (which should put the download into a pending retry state) versus an irrecoverable server/business failure.
  private func isConnectivityError(_ error: Error) -> Bool {
    if let caasError = error as? CaasError {
      switch caasError {
      case .networkError(let underlying):
        let lower = underlying.lowercased()
        return lower.contains("offline") ||
               lower.contains("internet") ||
               lower.contains("connection") ||
               lower.contains("network") ||
               lower.contains("unreachable")
      default:
        return false
      }
    }

    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet,
           .networkConnectionLost,
           .dataNotAllowed,
           .internationalRoamingOff:
        return true
      default:
        return false
      }
    }

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      switch nsError.code {
      case NSURLErrorNotConnectedToInternet,
           NSURLErrorNetworkConnectionLost,
           NSURLErrorDataNotAllowed,
           NSURLErrorInternationalRoamingOff:
        return true
      default:
        return false
      }
    }

    return false
  }
}
