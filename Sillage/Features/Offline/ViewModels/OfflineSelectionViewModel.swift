//
//  OfflineSelectionViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation
import Observation
import OSLog

/// A ViewModel responsible for managing the state of the offline map region selection process,
/// orchestrating GeoGarage CAAS package generation, downloads, state preservation, and recovery.
@Observable
@MainActor
final class OfflineSelectionViewModel {

  // MARK: - Injected Dependencies

  private let downloader: GeoGarageChartDownloaderProtocol
  private let packageService: GeoGaragePackageServiceProtocol
  private let downloadRepository: GeoGarageDownloadRepositoryProtocol
  private let preferencesService: PreferencesServiceProtocol
  let chartViewModel: ChartViewModel
  let offlineMapManager: OfflineMapManagerProtocol?

  // MARK: - Selection State Properties

  /// The geographically accurate bounding box derived from the UI crop box.
  @ObservationIgnored private(set) var selectedBounds: GeographicBoundingBox?

  /// Indicates whether the user is currently actively selecting an offline region.
  var isSelectionModeActive: Bool = false

  /// The estimated surface area of the currently selected bounds, used to warn the user about download limits.
  var estimatedArea: Measurement<UnitArea>?

  /// Indicates whether the currently selected area fits within the maximum allowed download limits.
  var isValidSize: Bool = false

  /// The default width ratio relative to the smallest map dimension.
  let cropBoxWidthRatio = 0.7

  /// The default aspect ratio (height/width) of the selection crop box.
  let cropBoxAspect = 0.75

  /// The user-defined dimension and position of the selection crop box. If nil, defaults are applied based on screen size.
  private(set) var cropRect: CGRect?

  // MARK: - GeoGarage Download State Properties

  var downloadPhase: GeoGarageDownloadPhaseState = .idle
  var selectedLayerID: String = ""
  var zoomMin: Int = 0
  var zoomMax: Int = 14
  var customName: String = ""

  @ObservationIgnored
  private var calculationTask: Task<Void, Never>?

  @ObservationIgnored
  private var currentTask: Task<Void, Never>?

  private let maxArea = AppConstants.Cartography.Offline.maxDownloadArea

  // MARK: - Computed Properties

  var downloadedCharts: [OfflineChartDownload] {
    downloadRepository.downloads
  }

  /// Total size in bytes of all locally downloaded offline packages.
  var totalDownloadedSizeBytes: Int64 {
    downloadedCharts.reduce(0) { $0 + $1.fileSizeBytes }
  }

  var isDownloading: Bool {
    switch downloadPhase {
    case .requesting, .generating, .downloading:
      return true
    case .idle, .completed, .failed, .cancelled:
      return false
    }
  }

  var currentViewportBounds: GeographicBoundingBox? {
    chartViewModel.currentVisibleBounds
  }

  var availableLayers: [GeoGarageLayer] {
    chartViewModel.availableGeoGarageLayers
  }

  // MARK: - Initializer

  init(
    downloader: GeoGarageChartDownloaderProtocol,
    packageService: GeoGaragePackageServiceProtocol,
    downloadRepository: GeoGarageDownloadRepositoryProtocol,
    preferencesService: PreferencesServiceProtocol,
    chartViewModel: ChartViewModel,
    offlineMapManager: OfflineMapManagerProtocol? = nil
  ) {
    self.downloader = downloader
    self.packageService = packageService
    self.downloadRepository = downloadRepository
    self.preferencesService = preferencesService
    self.chartViewModel = chartViewModel
    self.offlineMapManager = offlineMapManager

    if let firstLayer = chartViewModel.availableGeoGarageLayers.first {
      self.selectedLayerID = firstLayer.layer
    }
  }

  // MARK: - Selection Updates

  /// Updates the geographical bounding box linked to the UI selection area.
  /// It debounces the area computation to prevent excessive calculation during rapid map panning.
  /// - Parameter bounds: The new computed geographic bounding box.
  func updateBoundingBox(_ bounds: GeographicBoundingBox) {
    guard isSelectionModeActive else { return }
    self.selectedBounds = bounds

    calculationTask?.cancel()
    calculationTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(300))
        guard let self = self else { return }

        let area = bounds.estimatedArea
        self.estimatedArea = area
        self.isValidSize = area.converted(to: .squareNauticalMiles).value <= self.maxArea.value
      } catch is CancellationError {
        // Task was cancelled
      } catch {
        // Ignore
      }
    }
  }

  /// Updates the position and size of the selection crop box.
  /// - Parameter rect: The new final frame of the selection area in screen coordinates.
  func updateCropRect(_ rect: CGRect) {
    self.cropRect = rect
  }

  /// Fully clears the active selection and drops out of selection mode.
  func resetSelection() {
    offlineMapManager?.reset()
    isSelectionModeActive = false
    selectedBounds = nil
    estimatedArea = nil
    isValidSize = false
    cropRect = nil
    calculationTask?.cancel()
  }

  // MARK: - CAAS Download Pipeline

  /// Initiates an offline map download using the current selection or displayed chart source.
  /// - Parameter chartSource: The active chart source to derive layer information.
  func startDownload(chartSource: ChartSource?) {
    guard !isDownloading else { return }

    guard let bounds = selectedBounds ?? chartViewModel.currentVisibleBounds else {
      Logger.offline.warning("OfflineSelectionViewModel: startDownload called but no valid bounds found.")
      downloadPhase = .failed(errorMessage: String(localized: "No visible map viewport found. Pan or zoom the chart first."))
      return
    }

    guard let customerID = preferencesService.geoGarageCustomerID, !customerID.isEmpty else {
      downloadPhase = .failed(errorMessage: String(localized: "User is not authenticated with GeoGarage. Please login first."))
      return
    }

    // UI reset MUST be synchronous on the MainActor BEFORE the async download process
    isSelectionModeActive = false
    let zoneWKT = bounds.toWKT()
    selectedBounds = nil
    cropRect = nil
    calculationTask?.cancel()

    let layerToDownload: String
    if let source = chartSource, case .remoteGeoGarage(_, let layerID) = source {
      layerToDownload = layerID
    } else if !selectedLayerID.isEmpty {
      layerToDownload = selectedLayerID
    } else {
      layerToDownload = availableLayers.first?.layer ?? "shom"
    }

    let selectedLayer = availableLayers.first(where: { $0.layer == layerToDownload })
    let layerName = selectedLayer?.brandName ?? layerToDownload.uppercased()

    downloadPhase = .requesting
    let caasKey = AppConfiguration.shared.geoGarageCaasApiKey
    let zoomMax = self.zoomMax

    currentTask?.cancel()
    currentTask = Task { [weak self] in
      guard let self else { return }
      let token = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token") ?? ""
      let apiKey = (!caasKey.isEmpty && caasKey != "test_caas_api_key") ? caasKey : token

      await self.executeDownloadPipeline(
        apiKey: apiKey,
        customerID: customerID,
        layerID: layerToDownload,
        layerName: layerName,
        zoneWKT: zoneWKT,
        zoomMax: zoomMax
      )
    }
  }

  /// Initiates an offline chart package generation with explicit API key and customer ID.
  /// - Parameters:
  ///   - apiKey: Dedicated CAAS API key (or OAuth token).
  ///   - customerID: User's GeoGarage customer identifier.
  func startDownload(apiKey: String, customerID: String) {
    guard !isDownloading else { return }

    guard let bounds = selectedBounds ?? chartViewModel.currentVisibleBounds else {
      downloadPhase = .failed(errorMessage: String(localized: "No visible map viewport found. Pan or zoom the chart first."))
      return
    }

    let zoneWKT = bounds.toWKT()
    isSelectionModeActive = false
    selectedBounds = nil
    cropRect = nil
    calculationTask?.cancel()

    let layerToDownload = selectedLayerID.isEmpty ? (availableLayers.first?.layer ?? "shom") : selectedLayerID
    let selectedLayer = availableLayers.first(where: { $0.layer == layerToDownload })
    let layerName = selectedLayer?.brandName ?? layerToDownload.uppercased()

    downloadPhase = .requesting
    let zoomMax = self.zoomMax

    currentTask?.cancel()
    currentTask = Task { [weak self] in
      guard let self else { return }
      await self.executeDownloadPipeline(
        apiKey: apiKey,
        customerID: customerID,
        layerID: layerToDownload,
        layerName: layerName,
        zoneWKT: zoneWKT,
        zoomMax: zoomMax
      )
    }
  }

  /// Internal orchestration pipeline: requests the package, preserves state, polls until completion, and downloads the MBTiles archive.
  private func executeDownloadPipeline(
    apiKey: String,
    customerID: String,
    layerID: String,
    layerName: String,
    zoneWKT: String,
    zoomMax: Int
  ) async {
    guard !apiKey.isEmpty else {
      downloadPhase = .failed(errorMessage: CaasError.authenticationRequired.localizedDescription)
      return
    }

    let request = PackageRequest(
      layerID: layerID,
      zoneWKT: zoneWKT,
      zoomMax: zoomMax,
      format: .mbtiles,
      cipher: .v4
    )

    do {
      // 1. Request package generation on the CAAS backend
      let packageID = try await packageService.requestPackage(
        request,
        apiKey: apiKey,
        userID: customerID
      )

      // 2. CRITICAL (State Preservation): Persist pending download state before polling
      let pending = PendingCAASDownload(
        packageID: packageID,
        layerID: layerID,
        layerName: layerName,
        boundsWKT: zoneWKT,
        zoomMax: zoomMax,
        createdAt: Date()
      )
      preferencesService.pendingCAASDownload = pending

      // 3. Poll generation status until completed
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
    } catch let caasError as CaasError {
      downloadPhase = .failed(errorMessage: caasError.localizedDescription)
      preferencesService.pendingCAASDownload = nil
    } catch {
      downloadPhase = .failed(errorMessage: error.localizedDescription)
      preferencesService.pendingCAASDownload = nil
    }
  }

  /// Polls the CAAS server and downloads the archive upon success.
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
      if Task.isCancelled {
        downloadPhase = .cancelled
        preferencesService.pendingCAASDownload = nil
        return
      }

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

    guard let completedStatus = finalStatus,
          let rawURLString = completedStatus.url,
          let downloadURL = URL(string: rawURLString),
          let fileHash = completedStatus.md5 else {
      throw CaasError.downloadFailed(underlying: "Server generation completed without valid download URL or MD5 hash.")
    }

    // Download archive, validate streaming MD5, and persist to repository
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

  /// Resumes an in-flight CAAS download if state was preserved across app termination/crash.
  func resumePendingDownloadIfNeeded() async {
    guard let pending = preferencesService.pendingCAASDownload else { return }

    let alreadyDownloaded = downloadRepository.downloads.contains { $0.id == pending.packageID }
    if alreadyDownloaded {
      Logger.offline.info("Pending download \(pending.packageID.uuidString, privacy: .public) already completed in repository. Clearing pending state.")
      preferencesService.pendingCAASDownload = nil
      return
    }

    guard let customerID = preferencesService.geoGarageCustomerID, !customerID.isEmpty else {
      Logger.offline.warning("Cannot resume pending download: missing customer ID.")
      preferencesService.pendingCAASDownload = nil
      return
    }

    let caasKey = AppConfiguration.shared.geoGarageCaasApiKey
    let token = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token") ?? ""
    let apiKey = (!caasKey.isEmpty && caasKey != "test_caas_api_key") ? caasKey : token

    guard !apiKey.isEmpty else {
      Logger.offline.warning("Cannot resume pending download: missing API key.")
      preferencesService.pendingCAASDownload = nil
      return
    }

    Logger.offline.info("Resuming pending CAAS download \(pending.packageID.uuidString, privacy: .public) for layer '\(pending.layerID, privacy: .public)'")

    downloadPhase = .generating(progress: nil, message: "Resuming...")

    currentTask?.cancel()
    currentTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.pollAndDownloadArchive(
          packageID: pending.packageID,
          apiKey: apiKey,
          layerID: pending.layerID,
          layerName: pending.layerName,
          boundsWKT: pending.boundsWKT,
          zoomMax: pending.zoomMax
        )
      } catch is CancellationError {
        self.downloadPhase = .cancelled
        self.preferencesService.pendingCAASDownload = nil
      } catch let caasError as CaasError {
        self.downloadPhase = .failed(errorMessage: caasError.localizedDescription)
        self.preferencesService.pendingCAASDownload = nil
      } catch {
        self.downloadPhase = .failed(errorMessage: error.localizedDescription)
        self.preferencesService.pendingCAASDownload = nil
      }
    }
  }

  /// Cancels any in-flight download task and resets state.
  func cancelDownload() {
    Logger.offline.info("OfflineSelectionViewModel: cancelDownload called by user")
    currentTask?.cancel()
    currentTask = nil
    downloadPhase = .cancelled
    preferencesService.pendingCAASDownload = nil
    offlineMapManager?.cancelDownload()
  }

  /// Deletes a previously downloaded offline chart from disk and repository.
  /// - Parameter download: Record to delete.
  func deleteDownload(_ download: OfflineChartDownload) async throws(CaasError) {
    try await downloader.deleteLocalChart(id: download.id)
  }
}

typealias GeoGarageOfflineViewModel = OfflineSelectionViewModel
