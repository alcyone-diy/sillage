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

/// Thread-safe per-job progress throttling state evaluated synchronously on the downloader thread
/// via `OSAllocatedUnfairLock` to prevent spawning unstructured `MainActor` tasks on every raw network chunk.
nonisolated struct GeoGarageProgressThrottleState: Sendable {
  var lastUpdateTime: ContinuousClock.Instant?
  var lastReportedBytes: Int64 = 0
  var isClosed: Bool = false

  mutating func shouldEmit(
    received: Int64,
    total: Int64,
    now: ContinuousClock.Instant,
    minimumInterval: Duration = .milliseconds(250),
    minimumFractionDelta: Double = 0.01
  ) -> Bool {
    guard !isClosed, received >= lastReportedBytes else { return false }

    let isComplete = total > 0 && received >= total
    let hasElapsedInterval: Bool
    if let lastUpdateTime {
      hasElapsedInterval = (now - lastUpdateTime) >= minimumInterval
    } else {
      hasElapsedInterval = true
    }
    let bytesDelta = total > 0 ? Double(received - lastReportedBytes) / Double(total) : 0.0

    if isComplete || hasElapsedInterval || bytesDelta >= minimumFractionDelta {
      self.lastUpdateTime = now
      self.lastReportedBytes = received
      return true
    }
    return false
  }
}

/// A global, persistent service responsible for orchestrating GeoGarage CAAS chart package
/// queueing, state preservation across app terminations, and automatic recovery upon network reconnection,
/// while delegating unitary job execution to `GeoGarageDownloadPipelineExecutor`.
///
/// ### Architectural Rationale:
/// 1. **ViewModel Decoupling:**
///    Downloading a chart package is a long-lived operation that may take minutes over cellular/satellite connections.
///    Placing the execution pipeline inside `OfflineSelectionViewModel` caused downloads and recovery to be cancelled
///    whenever the selection panel was dismissed by the user. By isolating orchestration in this persistent service
///    instantiated within `AppEnvironment`, downloads proceed uninterrupted regardless of active view lifecycles.
///
/// 2. **Queue Orchestration vs. Stateless Pipeline Execution:**
///    `GeoGarageDownloadService` owns the `@MainActor` queue, `@Observable` UI state, 4 Hz throttling, and
///    `PreferencesService` synchronization, while `GeoGarageDownloadPipelineExecutor` executes individual jobs
///    without reading or mutating `activeDownloads`.
///
/// 3. **Structured Concurrency Network Observation:**
///    Instead of legacy `NotificationCenter` broadcasts, this service consumes `NetworkMonitorService.connectionStream()`,
///    an `AsyncStream<Bool>`, within an isolated `Task` loop with cooperative cancellation. When connectivity transitions
///    to `true`, pending downloads are seamlessly resumed.
///
/// 4. **Synchronous State Persistence Before Network Dispatch:**
///    To guarantee resilience against immediate app crashes or sudden terminations, `PendingCAASDownload` is written
///    synchronously to `PreferencesService` (UserDefaults) with `packageID = nil` *before* the first HTTP request is dispatched,
///    and updated immediately when intermediate pipeline events arrive.
///
/// 5. **Fine-Grained Local Connectivity Error Classification:**
///    Only true local connectivity outages (e.g. `URLError.notConnectedToInternet`, `URLError.networkConnectionLost`,
///    `URLError.dataNotAllowed`) transition the workflow into `.waitingForNetwork` while keeping the request queued.
///    Fatal errors (HTTP 401 Unauthorized, HTTP 400 Bad Request, server generation failures, MD5 corruption) are routed
///    to `.failed(errorMessage:)` and purge the pending state to prevent infinite retry loops and excessive battery drain.
@Observable
@MainActor
final class GeoGarageDownloadService: GeoGarageDownloadServiceProtocol {

  // MARK: - Concurrency Limits

  private let maxConcurrentDownloads = 2

  // MARK: - Injected Dependencies

  private let downloader: GeoGarageChartDownloaderProtocol
  private let downloadRepository: GeoGarageDownloadRepositoryProtocol
  private let preferencesService: PreferencesServiceProtocol
  private let networkMonitor: NetworkMonitorServiceProtocol
  private let messageService: MessageService
  private let keychainManager: any KeychainManaging
  private let pipelineExecutor: GeoGarageDownloadPipelineExecutor
  private let nowProvider: @Sendable () -> ContinuousClock.Instant

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
  private var downloadTasks: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]

  @ObservationIgnored
  private var networkObservationTask: Task<Void, Never>?

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
    networkMonitor: NetworkMonitorServiceProtocol,
    diskSpaceProvider: DiskSpaceProviderProtocol = SystemDiskSpaceProvider(),
    messageService: MessageService,
    keychainManager: any KeychainManaging = KeychainManager.shared,
    nowProvider: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
  ) {
    self.downloader = downloader
    self.downloadRepository = downloadRepository
    self.preferencesService = preferencesService
    self.networkMonitor = networkMonitor
    self.messageService = messageService
    self.keychainManager = keychainManager
    self.nowProvider = nowProvider
    self.pipelineExecutor = GeoGarageDownloadPipelineExecutor(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: downloadRepository,
      diskSpaceProvider: diskSpaceProvider
    )

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
    for entry in downloadTasks.values {
      entry.task.cancel()
    }
  }

  // MARK: - Public API

  func startDownload(
    layerID: String,
    layerName: String,
    zoneWKT: String,
    zoomMax: Int?,
    customName: String? = nil,
    replacesChartID: UUID? = nil
  ) {
    let appliedZoomMax = zoomMax ?? AppConstants.Cartography.Zoom.defaultOfflineZoomMax
    lastTerminalPhase = nil

    // Technical Design: Generate stable local UUID before network execution starts
    let localID = UUID()
    let pending = PendingCAASDownload(
      id: localID,
      packageID: nil,
      layerID: layerID,
      layerName: layerName,
      boundsWKT: zoneWKT,
      zoomMax: appliedZoomMax,
      createdAt: Date(),
      customName: customName,
      replacesChartID: replacesChartID
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

    Logger.offline.info("Enqueued offline chart download for '\(layerID, privacy: .public)' (id: \(localID.uuidString, privacy: .public), replaces: \(replacesChartID?.uuidString ?? "none", privacy: .public)). Total items in queue: \(self.activeDownloads.count, privacy: .public)")

    processQueue()
  }

  func resumePendingDownloadIfNeeded() async {
    lastTerminalPhase = nil

    // Purge any pending downloads already completed in repository
    preferencesService.pendingCAASDownloads.removeAll { pending in
      if let pkgID = pending.packageID, downloadRepository.downloads.contains(where: { $0.id == pkgID || $0.id == pending.id }) {
        Logger.offline.info("Pending download \(pending.id.uuidString, privacy: .public) already completed in repository. Clearing pending state.")
        return true
      }
      return false
    }

    let validPackageIDs = Set(preferencesService.pendingCAASDownloads.compactMap(\.packageID))
    await downloader.cleanupOrphanedDownloads(retainingPackageIDs: validPackageIDs)

    let currentPending = preferencesService.pendingCAASDownloads
    guard !currentPending.isEmpty else {
      activeDownloads.removeAll()
      sessionCompletedDownloadsCount = 0
      sessionTotalDownloadsCount = 0
      notifyProgressObservers()
      return
    }

    for pending in currentPending {
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
    if let entry = downloadTasks[id] {
      entry.task.cancel()
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
    for entry in downloadTasks.values {
      entry.task.cancel()
    }
    downloadTasks.removeAll()
    preferencesService.pendingCAASDownloads.removeAll()
    activeDownloads.removeAll()
    sessionCompletedDownloadsCount = 0
    sessionTotalDownloadsCount = 0
    lastTerminalPhase = .cancelled
    notifyProgressObservers()
  }

  func failDownload(with errorMessage: String, isAuthenticationError: Bool = false) {
    Logger.offline.error("GeoGarageDownloadService: failing all active downloads explicitly: \(errorMessage, privacy: .public)")
    for entry in downloadTasks.values {
      entry.task.cancel()
    }
    downloadTasks.removeAll()
    preferencesService.pendingCAASDownloads.removeAll()
    activeDownloads.removeAll()
    sessionCompletedDownloadsCount = 0
    sessionTotalDownloadsCount = 0
    lastTerminalPhase = .failed(errorMessage: errorMessage)
    notifyProgressObservers()
    postFailureMessage(errorMessage, isAuthenticationError: isAuthenticationError)
  }

  func failDownload(id: UUID, errorMessage: String, isAuthenticationError: Bool = false) {
    Logger.offline.error("GeoGarageDownloadService: download \(id.uuidString, privacy: .public) failed explicitly: \(errorMessage, privacy: .public)")
    downloadTasks[id]?.task.cancel()
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
    postFailureMessage(errorMessage, isAuthenticationError: isAuthenticationError)
  }

  func deleteDownload(_ download: OfflineChartDownload) async throws(CaasError) {
    try await downloader.deleteLocalChart(id: download.id)
  }

  // MARK: - Queue Processing & State Updates

  private func processQueue() {
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
        let targetID = activeDownloads[i].item.id

        availableSlots -= 1
        updateDownloadPhase(id: targetID, to: .requesting)

        let taskToken = UUID()
        downloadTasks[targetID]?.task.cancel()
        downloadTasks[targetID] = (
          token: taskToken,
          task: Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer {
              if self.downloadTasks[targetID]?.token == taskToken {
                self.downloadTasks.removeValue(forKey: targetID)
              }
            }

            let resolvedAccessToken: String?
            do {
              resolvedAccessToken = try await self.keychainManager.retrieveValidToken(for: GeoGarageKeychainKeys.accessToken)
            } catch {
              Logger.offline.error("Cannot start queued download \(targetID.uuidString, privacy: .public): Keychain access failed (\(error.localizedDescription, privacy: .public)).")
              self.failDownload(
                id: targetID,
                errorMessage: error.localizedDescription,
                isAuthenticationError: false
              )
              return
            }
            guard !Task.isCancelled,
                  let currentItem = self.activeDownloads.first(where: { $0.id == targetID })?.item else {
              return
            }

            let resolvedCustomer = self.preferencesService.geoGarageCustomerID

            guard let resolvedCustomer, !resolvedCustomer.isEmpty,
                  let resolvedAccessToken, !resolvedAccessToken.isEmpty else {
              Logger.offline.warning("Cannot start queued download \(targetID.uuidString, privacy: .public): missing credentials.")
              self.failDownload(
                id: targetID,
                errorMessage: String(localized: "User is not authenticated with GeoGarage. Please login first."),
                isAuthenticationError: true
              )
              return
            }

            guard self.networkMonitor.isConnected else {
              Logger.offline.info("Device is offline. Queuing pending download for '\(currentItem.layerID, privacy: .public)' in waiting state.")
              self.updateDownloadPhase(id: targetID, to: .waitingForNetwork(message: String(localized: "Waiting for network connection…")))
              return
            }

            await self.runDownloadPipeline(for: currentItem, accessToken: resolvedAccessToken)
          }
        )
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
    if let prefIndex = preferencesService.pendingCAASDownloads.firstIndex(where: { $0.id == id }) {
      preferencesService.pendingCAASDownloads[prefIndex] = preferencesService.pendingCAASDownloads[prefIndex].updating(packageID: packageID)
    }

    if let index = activeDownloads.firstIndex(where: { $0.id == id }) {
      let updated = activeDownloads[index].item.updating(packageID: packageID)
      activeDownloads[index] = ActiveCAASDownload(item: updated, phase: activeDownloads[index].phase)
    }
  }

  private func removeDownload(id: UUID) {
    downloadTasks[id]?.task.cancel()
    downloadTasks.removeValue(forKey: id)
    preferencesService.pendingCAASDownloads.removeAll { $0.id == id }
    activeDownloads.removeAll { $0.id == id }
  }

  // MARK: - Pipeline Orchestration & Event Handling

  private func runDownloadPipeline(
    for item: PendingCAASDownload,
    accessToken: String
  ) async {
    let localID = item.id

    guard !Task.isCancelled else {
      handlePipelineCancellation(id: localID)
      return
    }

    guard !accessToken.isEmpty else {
      failDownload(
        id: localID,
        errorMessage: CaasError.authenticationRequired.localizedDescription,
        isAuthenticationError: true
      )
      return
    }

    guard networkMonitor.isConnected else {
      Logger.offline.info("Device is offline. Queuing pending CAAS download for '\(item.layerID, privacy: .public)' until connection is restored.")
      updateDownloadPhase(id: localID, to: .waitingForNetwork(message: String(localized: "Waiting for network connection…")))
      return
    }

    // Per-job synchronous throttle gate: filters raw URLSession chunks at ~4 Hz (250 ms) or 1% delta
    // on the calling thread before hopping to MainActor, and seals immediately on exit via defer.
    let progressGate = OSAllocatedUnfairLock(initialState: GeoGarageProgressThrottleState())
    let nowProvider = self.nowProvider
    defer {
      progressGate.withLock { $0.isClosed = true }
    }

    do {
      let finalRecord = try await pipelineExecutor.execute(
        item: item,
        accessToken: accessToken,
        onEvent: { [weak self] event in
          await self?.handlePipelineEvent(event, for: localID)
        },
        onProgress: { [weak self] received, total in
          guard self != nil else { return }
          let now = nowProvider()
          let shouldUpdate = progressGate.withLock { state in
            state.shouldEmit(received: received, total: total, now: now)
          }
          guard shouldUpdate else { return }
          Task { @MainActor [weak self] in
            guard let self, !progressGate.withLock({ $0.isClosed }) else { return }
            self.applyThrottledDownloadProgress(id: localID, receivedBytes: received, totalBytes: total)
          }
        }
      )

      try Task.checkCancellation()
      guard activeDownloads.contains(where: { $0.id == localID }) else { return }

      sessionCompletedDownloadsCount += 1
      updateDownloadPhase(id: localID, to: .completed(finalRecord))
      removeDownload(id: localID)
      if activeDownloads.isEmpty {
        sessionCompletedDownloadsCount = 0
        sessionTotalDownloadsCount = 0
        lastTerminalPhase = .completed(finalRecord)
      }
      notifyProgressObservers()
      processQueue()
    } catch is CancellationError {
      handlePipelineCancellation(id: localID)
    } catch {
      if isConnectivityError(error) {
        Logger.offline.info("Network connectivity error during CAAS download: \(error.localizedDescription, privacy: .public). Queued in pending state.")
        updateDownloadPhase(id: localID, to: .waitingForNetwork(message: String(localized: "Waiting for network connection…")))
      } else {
        let isAuthError = (error as? CaasError) == .authenticationRequired
        failDownload(
          id: localID,
          errorMessage: error.localizedDescription,
          isAuthenticationError: isAuthError
        )
      }
    }
  }

  private func handlePipelineEvent(_ event: GeoGarageDownloadPipelineEvent, for id: UUID) {
    guard activeDownloads.contains(where: { $0.id == id }) else { return }

    switch event {
    case .packageIDAssigned(let packageID):
      updatePendingPackageID(id: id, packageID: packageID)
    case .generating(let progress, let message):
      updateDownloadPhase(id: id, to: .generating(progress: progress, message: message))
    case .downloadingStarted(let totalBytes):
      updateDownloadPhase(id: id, to: .downloading(receivedBytes: 0, totalBytes: totalBytes))
    }
  }

  private func applyThrottledDownloadProgress(id: UUID, receivedBytes: Int64, totalBytes: Int64) {
    // Phase and monotonicity guards prevent late or out-of-order ticks from overwriting terminal states
    // or regressing the progress bar during high-throughput updates.
    guard let index = activeDownloads.firstIndex(where: { $0.id == id }),
          case .downloading(let currentReceived, let currentTotal) = activeDownloads[index].phase else {
      return
    }
    if totalBytes == currentTotal, receivedBytes < currentReceived {
      return
    }
    updateDownloadPhase(id: id, to: .downloading(receivedBytes: receivedBytes, totalBytes: totalBytes))
  }

  private func handlePipelineCancellation(id: UUID) {
    guard activeDownloads.contains(where: { $0.id == id }) else { return }
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

  private func postFailureMessage(_ errorMessage: String, isAuthenticationError: Bool = false) {
    let appMessage = AppMessage(
      title: LocalizedStringResource("Offline Download Failed"),
      detail: .raw(errorMessage),
      severity: .error,
      category: .offlineCharts,
      intent: isAuthenticationError ? .openSettings(target: .geoGarage) : .none
    )
    messageService.post(appMessage)
  }
}
