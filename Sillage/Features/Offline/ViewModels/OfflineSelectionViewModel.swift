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

/// A ViewModel responsible for managing the UI state of the offline map region selection process
/// (crop box resizing, geographic bounding box calculation, area estimation).
/// Delegates all background package generation, persistence, network polling, and recovery to `GeoGarageDownloadServiceProtocol`.
@Observable
@MainActor
final class OfflineSelectionViewModel {

  // MARK: - Injected Dependencies

  let downloadService: GeoGarageDownloadServiceProtocol
  private let downloadRepository: GeoGarageDownloadRepositoryProtocol
  private let preferencesService: PreferencesServiceProtocol
  let chartViewModel: ChartViewModel
  let offlineMapManager: OfflineMapManagerProtocol?
  private let downloader: GeoGarageChartDownloaderProtocol?

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

  // MARK: - Configuration Properties

  var selectedLayerID: String = ""
  var zoomMin: Int = 0
  var zoomMax: Int = 14
  var customName: String = ""

  @ObservationIgnored
  private var calculationTask: Task<Void, Never>?

  private let maxArea = AppConstants.Cartography.Offline.maxDownloadArea

  // MARK: - Computed Properties Forwarded from Service / Repositories

  var downloadPhase: GeoGarageDownloadPhaseState {
    downloadService.downloadPhase
  }

  var downloadedCharts: [OfflineChartDownload] {
    downloadRepository.downloads
  }

  /// Total size in bytes of all locally downloaded offline packages.
  var totalDownloadedSize: Int64 {
    downloadedCharts.reduce(0) { $0 + $1.fileSizeBytes }
  }

  var isDownloading: Bool {
    downloadService.isDownloading
  }

  /// Normalized progress value between 0.0 and 1.0 if known during generation or downloading, or nil if indeterminate.
  var downloadProgress: Double? {
    downloadService.downloadProgress
  }

  var currentViewportBounds: GeographicBoundingBox? {
    chartViewModel.currentVisibleBounds
  }

  var availableLayers: [GeoGarageLayer] {
    chartViewModel.availableGeoGarageLayers
  }

  /// Downloaded offline charts grouped by GeoGarage chart type, sorted in alphabetical order.
  var groupedDownloadedCharts: [OfflineChartTypeGroup] {
    OfflineChartTypeGroup.group(downloadedCharts, availableLayers: availableLayers)
  }

  // MARK: - Initializers

  init(
    downloadService: GeoGarageDownloadServiceProtocol,
    downloadRepository: GeoGarageDownloadRepositoryProtocol,
    preferencesService: PreferencesServiceProtocol,
    chartViewModel: ChartViewModel,
    offlineMapManager: OfflineMapManagerProtocol? = nil,
    downloader: GeoGarageChartDownloaderProtocol? = nil
  ) {
    self.downloadService = downloadService
    self.downloadRepository = downloadRepository
    self.preferencesService = preferencesService
    self.chartViewModel = chartViewModel
    self.offlineMapManager = offlineMapManager
    self.downloader = downloader

    if let firstLayer = chartViewModel.availableGeoGarageLayers.first {
      self.selectedLayerID = firstLayer.layer
    }
  }

  /// Convenience initializer constructing a `GeoGarageDownloadService` when individual components are passed.
  convenience init(
    downloader: GeoGarageChartDownloaderProtocol,
    packageService: GeoGaragePackageServiceProtocol,
    downloadRepository: GeoGarageDownloadRepositoryProtocol,
    preferencesService: PreferencesServiceProtocol,
    chartViewModel: ChartViewModel,
    offlineMapManager: OfflineMapManagerProtocol? = nil,
    networkMonitor: NetworkMonitorServiceProtocol? = nil
  ) {
    let monitor = networkMonitor ?? NetworkMonitorService()
    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: downloadRepository,
      preferencesService: preferencesService,
      networkMonitor: monitor
    )
    self.init(
      downloadService: service,
      downloadRepository: downloadRepository,
      preferencesService: preferencesService,
      chartViewModel: chartViewModel,
      offlineMapManager: offlineMapManager,
      downloader: downloader
    )
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

  // MARK: - CAAS Download Actions

  /// Initiates an offline map download using the current selection or displayed chart source.
  /// - Parameter chartSource: The active chart source to derive layer information.
  func startDownload(chartSource: ChartSource?) {
    guard !isDownloading else { return }

    guard let bounds = selectedBounds ?? chartViewModel.currentVisibleBounds else {
      Logger.offline.warning("OfflineSelectionViewModel: startDownload called but no valid bounds found.")
      downloadService.failDownload(with: String(localized: "No visible map viewport found. Pan or zoom the chart first."))
      return
    }

    guard let customerID = preferencesService.geoGarageCustomerID, !customerID.isEmpty else {
      Logger.offline.warning("OfflineSelectionViewModel: startDownload called without authenticated customer ID.")
      downloadService.failDownload(with: String(localized: "User is not authenticated with GeoGarage. Please login first."))
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

    let caasKey = AppConfiguration.shared.geoGarageCaasApiKey
    let zoomMax = self.zoomMax

    Task { [weak self] in
      guard let self else { return }
      let token = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token") ?? ""
      let apiKey = (!caasKey.isEmpty && caasKey != "test_caas_api_key") ? caasKey : token

      self.downloadService.startDownload(
        layerID: layerToDownload,
        layerName: layerName,
        zoneWKT: zoneWKT,
        zoomMax: zoomMax,
        apiKey: apiKey,
        customerID: customerID
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
      Logger.offline.warning("OfflineSelectionViewModel: startDownload called but no valid bounds found.")
      downloadService.failDownload(with: String(localized: "No visible map viewport found. Pan or zoom the chart first."))
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
    let zoomMax = self.zoomMax

    downloadService.startDownload(
      layerID: layerToDownload,
      layerName: layerName,
      zoneWKT: zoneWKT,
      zoomMax: zoomMax,
      apiKey: apiKey,
      customerID: customerID
    )
  }

  /// Resumes an in-flight CAAS download if state was preserved across app termination/crash or network restoration.
  func resumePendingDownloadIfNeeded() async {
    await downloadService.resumePendingDownloadIfNeeded()
  }

  /// Cancels any in-flight download task and resets state.
  func cancelDownload() {
    Logger.offline.info("OfflineSelectionViewModel: cancelDownload called by user")
    downloadService.cancelDownload()
    offlineMapManager?.cancelDownload()
  }

  /// Deletes a previously downloaded offline chart from disk and repository.
  /// Encapsulates the routing choice between `GeoGarageChartDownloaderProtocol` and `GeoGarageDownloadServiceProtocol`.
  /// - Parameter download: Record to delete.
  func deleteDownload(_ download: OfflineChartDownload) async throws {
    if let downloader {
      try await downloader.deleteLocalChart(id: download.id)
    } else {
      try await downloadService.deleteDownload(download)
    }
  }
}

/// Represents a grouped collection of downloaded offline charts for a specific GeoGarage chart type (layer).
struct OfflineChartTypeGroup: Identifiable, Equatable, Sendable {
  var id: String { layerID }
  let layerID: String
  let title: String
  let downloads: [OfflineChartDownload]

  /// Groups offline downloads by their GeoGarage layer ID and sorts sections in strictly alphabetical order by title.
  /// Inside each group, downloads are sorted in descending chronological order (most recent first).
  static func group(
    _ downloads: [OfflineChartDownload],
    availableLayers: [GeoGarageLayer] = []
  ) -> [OfflineChartTypeGroup] {
    let grouped = Dictionary(grouping: downloads) { $0.layerID.lowercased() }

    return grouped.map { layerID, groupDownloads in
      let title: String = {
        if let matchingLayer = availableLayers.first(where: { $0.layer.lowercased() == layerID }) {
          return matchingLayer.brandName
        }
        if let firstLayerName = groupDownloads.first?.layerName, !firstLayerName.isEmpty {
          return firstLayerName
        }
        return layerID.uppercased()
      }()
      let sortedDownloads = groupDownloads.sorted { $0.downloadDate > $1.downloadDate }
      return OfflineChartTypeGroup(layerID: layerID, title: title, downloads: sortedDownloads)
    }
    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }
}

typealias GeoGarageOfflineViewModel = OfflineSelectionViewModel
