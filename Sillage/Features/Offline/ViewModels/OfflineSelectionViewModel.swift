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

  /// The geographically accurate bounding box defining the offline region to download.
  private(set) var selectedBounds: GeographicBoundingBox?

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

  /// The existing offline chart package being modified, if zone modification is underway.
  private(set) var chartToModify: OfflineChartDownload?

  /// The custom name to apply to the replacement chart package once downloaded.
  private(set) var pendingCustomName: String?

  /// The initial geographic bounds of the chart being modified, to align the crop box exactly on the existing zone.
  private(set) var initialBounds: GeographicBoundingBox?

  /// Clears initialBounds once it has been projected into cropRect by the map engine.
  func consumeInitialBounds() {
    self.initialBounds = nil
  }

  // MARK: - Configuration Properties

  var selectedLayerID: String = "" {
    didSet {
      if isSelectionModeActive {
        refreshOfflineMask()
      }
    }
  }
  var zoomMax: Int = AppConstants.Cartography.Zoom.defaultOfflineZoomMax

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

  /// Downloads to display on the map mask, excluding any chart currently undergoing zone modification.
  var availableDownloadedChartsForMask: [OfflineChartDownload] {
    if let chartToModify {
      return downloadedCharts.filter { $0.id != chartToModify.id }
    }
    return downloadedCharts
  }

  /// All chart items to be displayed in the UI, combining completed downloads and active/queued downloads.
  var allChartItems: [OfflineChartItem] {
    var items = downloadedCharts.map { OfflineChartItem.downloaded($0) }
    for active in downloadService.activeDownloads {
      items.append(.inProgress(active.item, phase: active.phase))
    }
    return items
  }

  /// Total physical size of all locally downloaded offline packages.
  var totalDownloadedSize: Measurement<UnitInformationStorage> {
    downloadedCharts.compactMap(\.fileSize).reduce(Measurement(value: 0, unit: .bytes), +)
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

  private let keychainManager: any KeychainManaging

  init(
    downloadService: GeoGarageDownloadServiceProtocol,
    downloadRepository: GeoGarageDownloadRepositoryProtocol,
    preferencesService: PreferencesServiceProtocol,
    chartViewModel: ChartViewModel,
    offlineMapManager: OfflineMapManagerProtocol? = nil,
    downloader: GeoGarageChartDownloaderProtocol? = nil,
    keychainManager: any KeychainManaging = KeychainManager.shared
  ) {
    self.downloadService = downloadService
    self.downloadRepository = downloadRepository
    self.preferencesService = preferencesService
    self.chartViewModel = chartViewModel
    self.offlineMapManager = offlineMapManager
    self.downloader = downloader
    self.keychainManager = keychainManager
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
    networkMonitor: NetworkMonitorServiceProtocol? = nil,
    messageService: MessageService,
    keychainManager: any KeychainManaging = KeychainManager.shared
  ) {
    let monitor = networkMonitor ?? NetworkMonitorService()
    let service = GeoGarageDownloadService(
      packageService: packageService,
      downloader: downloader,
      downloadRepository: downloadRepository,
      preferencesService: preferencesService,
      networkMonitor: monitor,
      messageService: messageService,
      keychainManager: keychainManager
    )
    self.init(
      downloadService: service,
      downloadRepository: downloadRepository,
      preferencesService: preferencesService,
      chartViewModel: chartViewModel,
      offlineMapManager: offlineMapManager,
      downloader: downloader,
      keychainManager: keychainManager
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
    chartToModify = nil
    pendingCustomName = nil
    initialBounds = nil
    zoomMax = AppConstants.Cartography.Zoom.defaultOfflineZoomMax
    chartViewModel.clearOfflineRegionHighlight()
    calculationTask?.cancel()
    chartViewModel.updateOfflineMaskState(
      isSelectionActive: false,
      activeLayerID: nil,
      selectedBounds: nil,
      downloads: []
    )
  }

  /// Enters region selection mode for creating a new offline chart.
  /// If `initialBounds` is provided, sets it as the starting bounding box.
  /// Otherwise, computes a centered box from the visible viewport.
  func startNewSelection(initialBounds: GeographicBoundingBox? = nil) {
    self.chartToModify = nil
    self.pendingCustomName = nil
    self.initialBounds = nil
    self.cropRect = nil
    self.zoomMax = AppConstants.Cartography.Zoom.defaultOfflineZoomMax
    chartViewModel.clearOfflineRegionHighlight()

    self.isSelectionModeActive = true

    if let initialBounds {
      self.updateBoundingBox(initialBounds)
    } else {
      self.selectedBounds = nil
      self.estimatedArea = nil
      self.isValidSize = false
    }
  }

  /// Enters region selection mode to modify the geographic boundary of an existing downloaded chart.
  /// - Parameters:
  ///   - download: The existing offline chart package whose zone is being changed.
  ///   - customName: Optional updated custom name from the edit session.
  ///   - padding: Viewport edge insets injected by the UI layer to frame the bounding box.
  func startModifyingZone(for download: OfflineChartDownload, customName: String? = nil, padding: UIEdgeInsets) {
    self.chartToModify = download
    self.selectedLayerID = download.layerID
    self.zoomMax = download.zoomMax
    if let customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      self.pendingCustomName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      self.pendingCustomName = download.customName
    }

    chartViewModel.clearOfflineRegionHighlight()

    if let bounds = download.geographicBounds {
      self.initialBounds = bounds
      self.selectedBounds = bounds
      self.estimatedArea = bounds.estimatedArea
      self.isValidSize = bounds.estimatedArea.converted(to: .squareNauticalMiles).value <= maxArea.value
      self.cropRect = nil

      chartViewModel.fitBounds(bounds, padding: padding, animated: false)
    } else {
      self.initialBounds = nil
      self.selectedBounds = nil
      self.cropRect = nil
    }

    self.isSelectionModeActive = true
  }

  /// Resolves the target GeoGarage layer identifier to download according to priority:
  /// 1. Explicitly selected layer (`selectedLayerID`)
  /// 2. Active chart layer from `chartViewModel.currentChartSource` (or optional override) if it's a remote GeoGarage layer
  /// 3. First available authorized layer (`availableLayers.first?.layer`)
  private func resolveTargetLayerID(explicitSource: ChartSource? = nil) -> String? {
    if !selectedLayerID.isEmpty {
      return selectedLayerID
    }
    let source = explicitSource ?? chartViewModel.currentChartSource
    if let source, case .remoteGeoGarage(_, let layerID) = source, !layerID.isEmpty {
      return layerID
    }
    return availableLayers.first?.layer
  }

  private var targetLayerID: String? {
    resolveTargetLayerID()
  }

  private func failWithFeedback(_ message: String, isAuthenticationError: Bool = false) {
    Logger.offline.warning("OfflineSelectionViewModel: \(message, privacy: .public)")
    downloadService.failDownload(with: message, isAuthenticationError: isAuthenticationError)
  }

  /// Validates and returns the target layer ID, failing the download service if unavailable.
  private func requireTargetLayerID(explicitSource: ChartSource? = nil) -> String? {
    guard let layerID = resolveTargetLayerID(explicitSource: explicitSource), !layerID.isEmpty else {
      failWithFeedback(String(localized: "No chart layer available for download. Please select a valid layer."))
      return nil
    }
    return layerID
  }

  /// Validates and returns the geographic bounding box for download, failing the download service if unavailable.
  private func requireDownloadBounds() -> GeographicBoundingBox? {
    guard let bounds = selectedBounds ?? chartViewModel.currentVisibleBounds else {
      failWithFeedback(String(localized: "No visible map viewport found. Pan or zoom the chart first."))
      return nil
    }
    return bounds
  }

  /// Triggers asynchronous calculation of the offline mask visual state on ChartViewModel.
  func refreshOfflineMask() {
    chartViewModel.updateOfflineMaskState(
      isSelectionActive: isSelectionModeActive,
      activeLayerID: targetLayerID,
      selectedBounds: isSelectionModeActive ? selectedBounds : nil,
      downloads: availableDownloadedChartsForMask
    )
  }

  // MARK: - CAAS Download Actions

  /// Initiates an offline map download using the current selection or displayed chart source.
  /// - Parameter chartSource: Optional explicit chart source override (defaults to `chartViewModel.currentChartSource`).
  func startDownload(chartSource: ChartSource? = nil) {
    guard let bounds = requireDownloadBounds() else { return }

    guard let customerID = preferencesService.geoGarageCustomerID, !customerID.isEmpty else {
      failWithFeedback(
        String(localized: "User is not authenticated with GeoGarage. Please login first."),
        isAuthenticationError: true
      )
      return
    }

    guard let layerToDownload = requireTargetLayerID(explicitSource: chartSource) else { return }

    let chartBeingReplaced = self.chartToModify
    let customNameToPreserve = self.pendingCustomName ?? chartBeingReplaced?.customName

    // UI reset MUST be synchronous on the MainActor BEFORE the async download process
    isSelectionModeActive = false
    let zoneWKT = bounds.toWKT()
    selectedBounds = nil
    cropRect = nil
    chartToModify = nil
    pendingCustomName = nil
    calculationTask?.cancel()

    let selectedLayer = availableLayers.first(where: { $0.layer == layerToDownload })
    let layerName = selectedLayer?.brandName ?? layerToDownload.uppercased()

    let zoomMax = self.zoomMax

    Task { [weak self] in
      guard let self else { return }

      // The package is requested with the user's token, not an embedded key: no token, no request.
      guard let token = await self.keychainManager.retrieveValidToken(for: GeoGarageKeychainKeys.accessToken) else {
        self.failWithFeedback(
          String(localized: "User is not authenticated with GeoGarage. Please login first."),
          isAuthenticationError: true
        )
        return
      }

      await self.processDownloadRequest(
        layerID: layerToDownload,
        layerName: layerName,
        zoneWKT: zoneWKT,
        zoomMax: zoomMax,
        accessToken: token,
        customerID: customerID,
        chartBeingReplaced: chartBeingReplaced,
        customName: customNameToPreserve
      )
    }
  }

  /// Initiates an offline chart package generation with explicit access token and customer ID.
  /// - Parameters:
  ///   - accessToken: OAuth2 access token of the signed-in user (`Authorization: Bearer`).
  ///   - customerID: User's GeoGarage customer identifier.
  func startDownload(accessToken: String, customerID: String) {
    guard let bounds = requireDownloadBounds() else { return }
    guard let layerToDownload = requireTargetLayerID() else { return }

    let chartBeingReplaced = self.chartToModify
    let customNameToPreserve = self.pendingCustomName ?? chartBeingReplaced?.customName

    isSelectionModeActive = false
    let zoneWKT = bounds.toWKT()
    selectedBounds = nil
    cropRect = nil
    chartToModify = nil
    pendingCustomName = nil
    calculationTask?.cancel()

    let selectedLayer = availableLayers.first(where: { $0.layer == layerToDownload })
    let layerName = selectedLayer?.brandName ?? layerToDownload.uppercased()
    let zoomMax = self.zoomMax

    Task { [weak self] in
      guard let self else { return }
      await self.processDownloadRequest(
        layerID: layerToDownload,
        layerName: layerName,
        zoneWKT: zoneWKT,
        zoomMax: zoomMax,
        accessToken: accessToken,
        customerID: customerID,
        chartBeingReplaced: chartBeingReplaced,
        customName: customNameToPreserve
      )
    }
  }

  /// Processes a validated download request, awaiting deletion of any replaced chart package before initiating download.
  private func processDownloadRequest(
    layerID: String,
    layerName: String,
    zoneWKT: String,
    zoomMax: Int,
    accessToken: String,
    customerID: String,
    chartBeingReplaced: OfflineChartDownload?,
    customName: String?
  ) async {
    self.downloadService.startDownload(
      layerID: layerID,
      layerName: layerName,
      zoneWKT: zoneWKT,
      zoomMax: zoomMax,
      accessToken: accessToken,
      customerID: customerID,
      customName: customName,
      replacesChartID: chartBeingReplaced?.id
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

  var id: UUID {
    switch self {
    case .downloaded(let download):
      return download.id
    case .inProgress(let pending, _):
      return pending.id
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
