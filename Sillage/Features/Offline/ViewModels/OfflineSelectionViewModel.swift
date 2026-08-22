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
  let downloadRepository: GeoGarageDownloadRepositoryProtocol
  private let preferencesService: PreferencesServiceProtocol
  let chartViewModel: ChartViewModel
  let offlineMapManager: OfflineMapManagerProtocol?
  private let downloader: GeoGarageChartDownloaderProtocol?

  // MARK: - Selection State Properties

  /// The geographically accurate bounding box derived from the UI crop box.
  @ObservationIgnored private(set) var selectedBounds: GeographicBoundingBox?

  /// Indicates whether the user is currently actively selecting an offline region.
  var isSelectionModeActive: Bool = false {
    didSet {
      refreshOfflineMask()
    }
  }

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

  var selectedLayerID: String = "" {
    didSet {
      if isSelectionModeActive {
        refreshOfflineMask()
      }
    }
  }
  var zoomMax: Int = 14

  @ObservationIgnored
  private var calculationTask: Task<Void, Never>?

  private let maxArea = AppConstants.Cartography.Offline.maxDownloadArea

  // MARK: - Computed Properties Forwarded from Service / Repositories

  /// Current download phase derived directly from the download service.
  var downloadPhase: GeoGarageDownloadPhaseState {
    downloadService.downloadPhase
  }

  var downloadedCharts: [OfflineChartDownload] {
    downloadRepository.downloads
  }

  /// All chart items to be displayed in the UI, combining completed downloads and active/queued downloads.
  var allChartItems: [OfflineChartItem] {
    var items = downloadedCharts.map { OfflineChartItem.downloaded($0) }
    for active in downloadService.activeDownloads {
      items.append(.inProgress(active.item, phase: active.phase))
    }
    return items
  }

  /// Total size in bytes of all locally downloaded offline packages.
  var totalDownloadedSize: Int64 {
    downloadedCharts.reduce(0) { $0 + ($1.fileSizeBytes ?? 0) }
  }

  var isDownloading: Bool {
    downloadService.isDownloading
  }

  var currentViewportBounds: GeographicBoundingBox? {
    chartViewModel.currentVisibleBounds
  }

  var availableLayers: [GeoGarageLayer] {
    chartViewModel.availableGeoGarageLayers
  }

  /// All offline charts (downloaded and in-progress) grouped by GeoGarage chart type, sorted in alphabetical order.
  var groupedCharts: [OfflineChartTypeGroup] {
    OfflineChartTypeGroup.group(items: allChartItems, availableLayers: availableLayers)
  }

  /// Downloaded offline charts grouped by GeoGarage chart type, sorted in alphabetical order (backwards compatibility).
  var groupedDownloadedCharts: [OfflineChartTypeGroup] {
    groupedCharts
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
  }

  deinit {
    calculationTask?.cancel()
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
    refreshOfflineMask()

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
    chartViewModel.updateOfflineMaskState(
      isSelectionActive: false,
      activeLayerID: nil,
      selectedBounds: nil,
      downloads: []
    )
  }

  /// Triggers asynchronous calculation of the offline mask visual state on ChartViewModel.
  func refreshOfflineMask() {
    let layerToFilter: String
    if !selectedLayerID.isEmpty {
      layerToFilter = selectedLayerID
    } else if let source = chartViewModel.currentChartSource, case .remoteGeoGarage(_, let layerID) = source {
      layerToFilter = layerID
    } else {
      layerToFilter = availableLayers.first?.layer ?? ""
    }

    chartViewModel.updateOfflineMaskState(
      isSelectionActive: isSelectionModeActive,
      activeLayerID: layerToFilter,
      selectedBounds: isSelectionModeActive ? selectedBounds : nil,
      downloads: downloadedCharts
    )
  }

  // MARK: - CAAS Download Actions

  /// Initiates an offline map download using the current selection or displayed chart source.
  /// - Parameter chartSource: The active chart source to derive layer information.
  func startDownload(chartSource: ChartSource?) {
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
    if !selectedLayerID.isEmpty {
      layerToDownload = selectedLayerID
    } else if let source = chartSource, case .remoteGeoGarage(_, let layerID) = source {
      layerToDownload = layerID
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

  /// Cancels a specific in-flight or queued download by its unique ID.
  func cancelDownload(id: UUID) {
    Logger.offline.info("OfflineSelectionViewModel: cancelDownload called for \(id.uuidString, privacy: .public)")
    downloadService.cancelDownload(id: id)
  }

  /// Cancels all in-flight or queued download tasks and resets state.
  func cancelDownload() {
    Logger.offline.info("OfflineSelectionViewModel: cancelDownload called by user for all active downloads")
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

  /// Deletes a chart item (cancels if in progress or deletes package from disk if already downloaded).
  /// - Parameter item: Item to delete or cancel.
  func deleteItem(_ item: OfflineChartItem) async throws {
    switch item {
    case .downloaded(let download):
      try await deleteDownload(download)
    case .inProgress(let pending, _):
      Logger.offline.info("Cancelling in-progress download for layer '\(item.layerName, privacy: .public)' (id: \(pending.id.uuidString, privacy: .public)) via user swipe-to-delete.")
      cancelDownload(id: pending.id)
    }
  }
}

/// Represents an item displayed in the Offline Charts list, which can either be a fully downloaded package
/// or an in-progress / pending download package.
enum OfflineChartItem: Identifiable, Equatable, Sendable {
  case downloaded(OfflineChartDownload)
  case inProgress(PendingCAASDownload, phase: GeoGarageDownloadPhaseState)

  var id: String {
    switch self {
    case .downloaded(let download):
      return download.id.uuidString
    case .inProgress(let pending, _):
      return pending.id.uuidString
    }
  }

  var layerID: String {
    switch self {
    case .downloaded(let download):
      return download.layerID
    case .inProgress(let pending, _):
      return pending.layerID
    }
  }

  var layerName: String {
    switch self {
    case .downloaded(let download):
      return download.layerName
    case .inProgress(let pending, _):
      return pending.layerName
    }
  }

  /// Presentation title for the offline chart item, respecting custom name override if defined.
  var displayName: String {
    switch self {
    case .downloaded(let download):
      if let custom = download.customName, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return custom.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      if !download.layerName.isEmpty {
        return download.layerName
      }
      return download.downloadDate.formatted(date: .abbreviated, time: .shortened)
    case .inProgress(let pending, _):
      return pending.layerName.isEmpty ? pending.createdAt.formatted(date: .abbreviated, time: .shortened) : pending.layerName
    }
  }

  var date: Date {
    switch self {
    case .downloaded(let download):
      return download.downloadDate
    case .inProgress(let pending, _):
      return pending.createdAt
    }
  }

  /// Geographic boundary as a rectangular WKT POLYGON (BBOX).
  var boundsWKT: String {
    switch self {
    case .downloaded(let download):
      return download.boundsWKT
    case .inProgress(let pending, _):
      return pending.boundsWKT
    }
  }

  /// Geographic bounding box parsed from WKT polygon for map camera framing.
  var geographicBounds: GeographicBoundingBox? {
    boundsWKT.isEmpty ? nil : GeographicBoundingBox(wkt: boundsWKT)
  }
}

/// Represents a grouped collection of offline charts (downloaded or in progress) for a specific GeoGarage chart type (layer).
struct OfflineChartTypeGroup: Identifiable, Equatable, Sendable {
  var id: String { layerID }
  let layerID: String
  let title: String
  let items: [OfflineChartItem]

  /// Backwards compatibility accessor returning only downloaded chart packages.
  var downloads: [OfflineChartDownload] {
    items.compactMap { item in
      if case .downloaded(let download) = item {
        return download
      }
      return nil
    }
  }

  init(layerID: String, title: String, items: [OfflineChartItem]) {
    self.layerID = layerID
    self.title = title
    self.items = items
  }

  init(layerID: String, title: String, downloads: [OfflineChartDownload]) {
    self.layerID = layerID
    self.title = title
    self.items = downloads.map { OfflineChartItem.downloaded($0) }
  }

  /// Groups offline chart items by their GeoGarage layer ID and sorts sections in strictly alphabetical order by title.
  /// Inside each group, items are sorted in descending chronological order (most recent first).
  static func group(
    items: [OfflineChartItem],
    availableLayers: [GeoGarageLayer] = []
  ) -> [OfflineChartTypeGroup] {
    let grouped = Dictionary(grouping: items) { $0.layerID.lowercased() }

    return grouped.map { layerID, groupItems in
      let title: String = {
        if let matchingLayer = availableLayers.first(where: { $0.layer.lowercased() == layerID }) {
          return matchingLayer.brandName
        }
        if let firstLayerName = groupItems.first?.layerName, !firstLayerName.isEmpty {
          return firstLayerName
        }
        return layerID.uppercased()
      }()
      let sortedItems = groupItems.sorted { $0.date > $1.date }
      return OfflineChartTypeGroup(layerID: layerID, title: title, items: sortedItems)
    }
    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  /// Convenience overload grouping completed downloads.
  static func group(
    _ downloads: [OfflineChartDownload],
    availableLayers: [GeoGarageLayer] = []
  ) -> [OfflineChartTypeGroup] {
    let items = downloads.map { OfflineChartItem.downloaded($0) }
    return group(items: items, availableLayers: availableLayers)
  }
}

typealias GeoGarageOfflineViewModel = OfflineSelectionViewModel
