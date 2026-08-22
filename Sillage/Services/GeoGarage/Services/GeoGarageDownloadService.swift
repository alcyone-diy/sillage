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
import os
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

  // MARK: - Concurrency Limits

  private let maxConcurrentDownloads = 2

  // MARK: - Injected Dependencies

  private let packageService: GeoGaragePackageServiceProtocol
  private let downloader: GeoGarageChartDownloaderProtocol
  private let downloadRepository: GeoGarageDownloadRepositoryProtocol
  private let preferencesService: PreferencesServiceProtocol
  private let networkMonitor: NetworkMonitorServiceProtocol

  // MARK: - State Properties

  /// Number of completed downloads in the current active download session.
  private(set) var sessionCompletedDownloadsCount: Int = 0

  /// Total number of downloads accounted for in the current active download session.
  private(set) var sessionTotalDownloadsCount: Int = 0

  /// Observable collection of all active and queued CAAS downloads.
  private(set) var activeDownloads: [ActiveCAASDownload] = [] {
    didSet {
      let currentPhase = downloadPhase
      let continuations = stateContinuationsLock.withLock { Array($0.values) }
      for cont in continuations {
        cont.yield(currentPhase)
      }
      notifyProgressObservers()
    }
  }

  private var lastTerminalPhase: GeoGarageDownloadPhaseState? {
    didSet {
      let currentPhase = downloadPhase
      let continuations = stateContinuationsLock.withLock { Array($0.values) }
      for cont in continuations {
        cont.yield(currentPhase)
      }
      notifyProgressObservers()
    }
  }

  /// High-level download phase representing the primary active download, or last terminal state, or idle.
  var downloadPhase: GeoGarageDownloadPhaseState {
    activeDownloads.first?.phase ?? lastTerminalPhase ?? .idle
  }

  @ObservationIgnored
  private let stateContinuationsLock = OSAllocatedUnfairLock<[UUID: AsyncStream<GeoGarageDownloadPhaseState>.Continuation]>(initialState: [:])

  @ObservationIgnored
  private let progressContinuationsLock = OSAllocatedUnfairLock<[UUID: AsyncStream<Double?>.Continuation]>(initialState: [:])

  @ObservationIgnored
  private var lastProgressUpdateDate: [UUID: Date] = [:]

  @ObservationIgnored
  private var lastReportedBytes: [UUID: Int64] = [:]

  @ObservationIgnored
  private var downloadTasks: [UUID: Task<Void, Never>] = [:]

  @ObservationIgnored
  private var networkObservationTask: Task<Void, Never>?

  @ObservationIgnored
  private var cachedApiKey: String?

  @ObservationIgnored
  private var cachedCustomerID: String?

  // MARK: - Computed Properties

  var isDownloading: Bool {
    activeDownloads.contains {
      switch $0.phase {
      case .queued, .waitingForNetwork, .requesting, .generating, .downloading:
        return true
      case .idle, .completed, .failed, .cancelled:
        return false
      }
    }
  }

  /// Overall composite download progress across all active, generating, downloading, and queued charts in the current session (0.0 to 1.0).
  var globalDownloadProgress: Double? {
    guard isDownloading, !activeDownloads.isEmpty else { return nil }
    let totalItems = max(activeDownloads.count + sessionCompletedDownloadsCount, sessionTotalDownloadsCount, 1)
    let completedWeight = Double(sessionCompletedDownloadsCount) * 1.0
    let activeWeight = activeDownloads.reduce(0.0) { sum, download in
      sum + download.progress
    }
    let progress = (completedWeight + activeWeight) / Double(totalItems)
    return min(max(progress, 0.0), 1.0)
  }

  func downloadStateStream() -> AsyncStream<GeoGarageDownloadPhaseState> {
    let id = UUID()
    let initialPhase = self.downloadPhase
    return AsyncStream { [stateContinuationsLock] continuation in
      continuation.yield(initialPhase)
      stateContinuationsLock.withLock {
        $0[id] = continuation
      }
      continuation.onTermination = { [stateContinuationsLock] _ in
        stateContinuationsLock.withLock {
          _ = $0.removeValue(forKey: id)
        }
      }
    }
  }

  func downloadProgressStream() -> AsyncStream<Double?> {
    let id = UUID()
    let initialProgress = self.globalDownloadProgress
    return AsyncStream { [progressContinuationsLock] continuation in
      continuation.yield(initialProgress)
      progressContinuationsLock.withLock {
        $0[id] = continuation
      }
      continuation.onTermination = { [progressContinuationsLock] _ in
        progressContinuationsLock.withLock {
          _ = $0.removeValue(forKey: id)
        }
      }
    }
  }

  private func notifyProgressObservers() {
    let currentProgress = globalDownloadProgress
    let continuations = progressContinuationsLock.withLock { Array($0.values) }
    for cont in continuations {
      cont.yield(currentProgress)
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

    // Restore any existing persisted pending downloads into queued state
    self.activeDownloads = preferencesService.pendingCAASDownloads.map {
      ActiveCAASDownload(item: $0, phase: .queued)
    }
    self.sessionTotalDownloadsCount = self.activeDownloads.count
    self.sessionCompletedDownloadsCount = 0

    // Technical Design: Listen to modern AsyncStream from NetworkMonitorService to auto-resume queued requests
    self.networkObservationTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      for await isConnected in self.networkMonitor.connectionStream() {
        guard !Task.isCancelled else { break }
        if isConnected {
          for i in 0..<self.activeDownloads.count {
            if case .waitingForNetwork = self.activeDownloads[i].phase {
              self.activeDownloads[i] = ActiveCAASDownload(item: self.activeDownloads[i].item, phase: .queued)
            }
          }
          self.processQueue()
        }
      }
    }
  }

  deinit {
    networkObservationTask?.cancel()
    for task in downloadTasks.values {
      task.cancel()
    }
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
    lastTerminalPhase = nil

    // Technical Design: Generate stable local UUID before network execution starts
    let localID = UUID()
    let pending = PendingCAASDownload(
      id: localID,
      packageID: nil,
      layerID: layerID,
      layerName: layerName,
      boundsWKT: zoneWKT,
      zoomMax: zoomMax,
      createdAt: Date()
    )

    // If starting a new session from 0 active downloads, reset completed count
    if activeDownloads.isEmpty {
      sessionCompletedDownloadsCount = 0
      sessionTotalDownloadsCount = 1
    } else {
      sessionTotalDownloadsCount = max(sessionTotalDownloadsCount + 1, activeDownloads.count + 1 + sessionCompletedDownloadsCount)
    }

    preferencesService.pendingCAASDownloads.append(pending)
    activeDownloads.append(ActiveCAASDownload(item: pending, phase: .queued))
    notifyProgressObservers()

    Logger.offline.info("Enqueued offline chart download for '\(layerID, privacy: .public)' (id: \(localID.uuidString, privacy: .public)). Total items in queue: \(self.activeDownloads.count, privacy: .public)")

    processQueue(apiKey: apiKey, customerID: customerID)
  }

  func resumePendingDownloadIfNeeded() async {
    lastTerminalPhase = nil

    // Purge any pending downloads already completed in repository
    var remaining: [PendingCAASDownload] = []
    for pending in preferencesService.pendingCAASDownloads {
      if let pkgID = pending.packageID, downloadRepository.downloads.contains(where: { $0.id == pkgID || $0.id == pending.id }) {
        Logger.offline.info("Pending download \(pending.id.uuidString, privacy: .public) already completed in repository. Clearing pending state.")
      } else {
        remaining.append(pending)
      }
    }
    preferencesService.pendingCAASDownloads = remaining

    guard !remaining.isEmpty else {
      activeDownloads.removeAll()
      sessionCompletedDownloadsCount = 0
      sessionTotalDownloadsCount = 0
      notifyProgressObservers()
      return
    }

    for pending in remaining {
      if !activeDownloads.contains(where: { $0.id == pending.id }) {
        activeDownloads.append(ActiveCAASDownload(item: pending, phase: .queued))
      }
    }
    sessionTotalDownloadsCount = activeDownloads.count
    sessionCompletedDownloadsCount = 0
    notifyProgressObservers()

    processQueue()
  }

  func cancelDownload(id: UUID) {
    Logger.offline.info("GeoGarageDownloadService: cancelDownload called for \(id.uuidString, privacy: .public)")
    if let task = downloadTasks[id] {
      task.cancel()
      downloadTasks.removeValue(forKey: id)
    }
    removeDownload(id: id)
    sessionTotalDownloadsCount = max(sessionCompletedDownloadsCount + activeDownloads.count, max(0, sessionTotalDownloadsCount - 1))
    if activeDownloads.isEmpty {
      sessionCompletedDownloadsCount = 0
      sessionTotalDownloadsCount = 0
      lastTerminalPhase = .cancelled
    }
    notifyProgressObservers()
    processQueue()
  }

  func cancelDownload() {
    Logger.offline.info("GeoGarageDownloadService: cancelDownload called for all active/queued downloads")
    for task in downloadTasks.values {
      task.cancel()
    }
    downloadTasks.removeAll()
    preferencesService.pendingCAASDownloads.removeAll()
    activeDownloads.removeAll()
    sessionCompletedDownloadsCount = 0
    sessionTotalDownloadsCount = 0
    lastTerminalPhase = .cancelled
    notifyProgressObservers()
  }

  func failDownload(with errorMessage: String) {
    Logger.offline.error("GeoGarageDownloadService: failing all active downloads explicitly: \(errorMessage, privacy: .public)")
    for task in downloadTasks.values {
      task.cancel()
    }
    downloadTasks.removeAll()
    preferencesService.pendingCAASDownloads.removeAll()
    activeDownloads.removeAll()
    sessionCompletedDownloadsCount = 0
    sessionTotalDownloadsCount = 0
    lastTerminalPhase = .failed(errorMessage: errorMessage)
    notifyProgressObservers()
  }

  func failDownload(id: UUID, errorMessage: String) {
    Logger.offline.error("GeoGarageDownloadService: download \(id.uuidString, privacy: .public) failed explicitly: \(errorMessage, privacy: .public)")
    downloadTasks[id]?.cancel()
    downloadTasks.removeValue(forKey: id)
    updateDownloadPhase(id: id, to: .failed(errorMessage: errorMessage))
    removeDownload(id: id)
    sessionTotalDownloadsCount = max(sessionCompletedDownloadsCount + activeDownloads.count, max(0, sessionTotalDownloadsCount - 1))
    if activeDownloads.isEmpty {
      sessionCompletedDownloadsCount = 0
      sessionTotalDownloadsCount = 0
      lastTerminalPhase = .failed(errorMessage: errorMessage)
    }
    notifyProgressObservers()
    processQueue()
  }

  func deleteDownload(_ download: OfflineChartDownload) async throws(CaasError) {
    try await downloader.deleteLocalChart(id: download.id)
  }

  // MARK: - Queue Processing & State Updates

  private func processQueue(apiKey: String? = nil, customerID: String? = nil) {
    if let apiKey { self.cachedApiKey = apiKey }
    if let customerID { self.cachedCustomerID = customerID }

    guard !activeDownloads.isEmpty else { return }

    let activeRunningCount = activeDownloads.filter {
      switch $0.phase {
      case .requesting, .generating, .downloading, .waitingForNetwork:
        return true
      case .queued, .idle, .completed, .failed, .cancelled:
        return false
      }
    }.count

    var availableSlots = max(0, maxConcurrentDownloads - activeRunningCount)
    guard availableSlots > 0 else {
      Logger.offline.debug("Download queue: \(activeRunningCount, privacy: .public)/\(self.maxConcurrentDownloads, privacy: .public) active slots occupied.")
      return
    }

    for i in 0..<activeDownloads.count {
      guard availableSlots > 0 else { break }
      if case .queued = activeDownloads[i].phase {
        let pending = activeDownloads[i].item
        let targetID = pending.id

        availableSlots -= 1
        updateDownloadPhase(id: targetID, to: .requesting)

        downloadTasks[targetID]?.cancel()
        downloadTasks[targetID] = Task { @MainActor [weak self] in
          guard let self = self else { return }

          let resolvedCustomer = self.cachedCustomerID ?? self.preferencesService.geoGarageCustomerID ?? ""
          let caasKey = AppConfiguration.shared.geoGarageCaasApiKey
          let token = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token") ?? ""
          let resolvedApiKey = self.cachedApiKey ?? ((!caasKey.isEmpty && caasKey != "test_caas_api_key") ? caasKey : token)

          guard !resolvedCustomer.isEmpty && !resolvedApiKey.isEmpty else {
            Logger.offline.warning("Cannot start queued download \(targetID.uuidString, privacy: .public): missing credentials.")
            self.failDownload(id: targetID, errorMessage: String(localized: "User is not authenticated with GeoGarage. Please login first."))
            return
          }

          guard self.networkMonitor.isConnected else {
            Logger.offline.info("Device is offline. Queuing pending download for '\(pending.layerID, privacy: .public)' in waiting state.")
            self.updateDownloadPhase(id: targetID, to: .waitingForNetwork(message: String(localized: "Waiting for network connection…")))
            return
          }

          await self.executeDownloadPipeline(
            apiKey: resolvedApiKey,
            customerID: resolvedCustomer,
            layerID: pending.layerID,
            layerName: pending.layerName,
            zoneWKT: pending.boundsWKT,
            zoomMax: pending.zoomMax,
            existingPackageID: pending.packageID,
            localID: targetID
          )
        }
      }
    }
  }

  private func updateDownloadPhase(id: UUID, to newPhase: GeoGarageDownloadPhaseState) {
    if let index = activeDownloads.firstIndex(where: { $0.id == id }) {
      activeDownloads[index] = ActiveCAASDownload(item: activeDownloads[index].item, phase: newPhase)
      notifyProgressObservers()
    }
  }

  private func updatePendingPackageID(id: UUID, packageID: UUID) {
    if let index = activeDownloads.firstIndex(where: { $0.id == id }) {
      let old = activeDownloads[index].item
      let updated = PendingCAASDownload(
        id: old.id,
        packageID: packageID,
        layerID: old.layerID,
        layerName: old.layerName,
        boundsWKT: old.boundsWKT,
        zoomMax: old.zoomMax,
        createdAt: old.createdAt
      )
      activeDownloads[index] = ActiveCAASDownload(item: updated, phase: activeDownloads[index].phase)
      if let prefIndex = preferencesService.pendingCAASDownloads.firstIndex(where: { $0.id == id }) {
        preferencesService.pendingCAASDownloads[prefIndex] = updated
      }
    }
  }

  private func removeDownload(id: UUID) {
    downloadTasks[id]?.cancel()
    downloadTasks.removeValue(forKey: id)
    preferencesService.pendingCAASDownloads.removeAll { $0.id == id }
    activeDownloads.removeAll { $0.id == id }
  }

  // MARK: - Pipeline Execution

  private func executeDownloadPipeline(
    apiKey: String,
    customerID: String,
    layerID: String,
    layerName: String,
    zoneWKT: String,
    zoomMax: Int,
    existingPackageID: UUID?,
    localID: UUID
  ) async {
    guard !Task.isCancelled else {
      removeDownload(id: localID)
      sessionTotalDownloadsCount = max(sessionCompletedDownloadsCount + activeDownloads.count, max(0, sessionTotalDownloadsCount - 1))
      if activeDownloads.isEmpty {
        sessionCompletedDownloadsCount = 0
        sessionTotalDownloadsCount = 0
        lastTerminalPhase = .cancelled
      }
      notifyProgressObservers()
      processQueue()
      return
    }

    guard !apiKey.isEmpty else {
      updateDownloadPhase(id: localID, to: .failed(errorMessage: CaasError.authenticationRequired.localizedDescription))
      removeDownload(id: localID)
      sessionTotalDownloadsCount = max(sessionCompletedDownloadsCount + activeDownloads.count, max(0, sessionTotalDownloadsCount - 1))
      if activeDownloads.isEmpty {
        sessionCompletedDownloadsCount = 0
        sessionTotalDownloadsCount = 0
        lastTerminalPhase = .failed(errorMessage: CaasError.authenticationRequired.localizedDescription)
      }
      notifyProgressObservers()
      processQueue()
      return
    }

    guard networkMonitor.isConnected else {
      Logger.offline.info("Device is offline. Queuing pending CAAS download for '\(layerID, privacy: .public)' until connection is restored.")
      updateDownloadPhase(id: localID, to: .waitingForNetwork(message: String(localized: "Waiting for network connection…")))
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
        updatePendingPackageID(id: localID, packageID: packageID)
      }

      try Task.checkCancellation()

      try await pollAndDownloadArchive(
        packageID: packageID,
        localID: localID,
        apiKey: apiKey,
        layerID: layerID,
        layerName: layerName,
        boundsWKT: zoneWKT,
        zoomMax: zoomMax
      )
    } catch is CancellationError {
      removeDownload(id: localID)
      sessionTotalDownloadsCount = max(sessionCompletedDownloadsCount + activeDownloads.count, max(0, sessionTotalDownloadsCount - 1))
      if activeDownloads.isEmpty {
        sessionCompletedDownloadsCount = 0
        sessionTotalDownloadsCount = 0
        lastTerminalPhase = .cancelled
      }
      notifyProgressObservers()
      processQueue()
    } catch {
      if isConnectivityError(error) {
        Logger.offline.info("Network connectivity error during CAAS download: \(error.localizedDescription, privacy: .public). Queued in pending state.")
        updateDownloadPhase(id: localID, to: .waitingForNetwork(message: String(localized: "Waiting for network connection…")))
      } else {
        Logger.offline.error("Fatal error during CAAS download: \(error.localizedDescription, privacy: .public)")
        updateDownloadPhase(id: localID, to: .failed(errorMessage: error.localizedDescription))
        removeDownload(id: localID)
        sessionTotalDownloadsCount = max(sessionCompletedDownloadsCount + activeDownloads.count, max(0, sessionTotalDownloadsCount - 1))
        if activeDownloads.isEmpty {
          sessionCompletedDownloadsCount = 0
          sessionTotalDownloadsCount = 0
          lastTerminalPhase = .failed(errorMessage: error.localizedDescription)
        }
        notifyProgressObservers()
        processQueue()
      }
    }
  }

  private func pollAndDownloadArchive(
    packageID: UUID,
    localID: UUID,
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
      updateDownloadPhase(id: localID, to: .generating(progress: progress, message: msg))

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
    updateDownloadPhase(id: localID, to: .downloading(receivedBytes: 0, totalBytes: totalBytes))

    let record = try await downloader.download(
      packageID: packageID,
      downloadURL: downloadURL,
      expectedMD5: fileHash,
      layerID: layerID,
      layerName: layerName,
      boundsWKT: boundsWKT,
      zoomMax: zoomMax,
      apiKey: apiKey,
      localID: localID,
      progressHandler: { [weak self] received, total in
        Task { @MainActor [weak self] in
          guard let self = self else { return }
          // Throttle progress events to ~4 Hz (250ms) or 1% delta to protect MainActor & battery
          let now = Date()
          let lastDate = self.lastProgressUpdateDate[localID] ?? .distantPast
          let lastBytes = self.lastReportedBytes[localID] ?? 0
          let isComplete = total > 0 && received >= total
          let timeDelta = now.timeIntervalSince(lastDate)
          let bytesDelta = total > 0 ? Double(received - lastBytes) / Double(total) : 0.0

          if isComplete || timeDelta >= 0.25 || bytesDelta >= 0.01 {
            self.lastProgressUpdateDate[localID] = now
            self.lastReportedBytes[localID] = received
            self.updateDownloadPhase(id: localID, to: .downloading(receivedBytes: received, totalBytes: total))
          }
        }
      }
    )

    lastProgressUpdateDate.removeValue(forKey: localID)
    lastReportedBytes.removeValue(forKey: localID)

    sessionCompletedDownloadsCount += 1
    updateDownloadPhase(id: localID, to: .completed(record))
    removeDownload(id: localID)
    if activeDownloads.isEmpty {
      sessionCompletedDownloadsCount = 0
      sessionTotalDownloadsCount = 0
      lastTerminalPhase = .completed(record)
    }
    notifyProgressObservers()
    processQueue()
  }

  // MARK: - Error Classification Helper

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
