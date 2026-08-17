//
//  GeoGarageOfflineViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

/// Represents the high-level observable state of a GeoGarage CAAS offline download workflow.
enum GeoGarageDownloadPhaseState: Equatable, Sendable {
  case idle
  case requesting
  case generating(progress: Double?, message: String)
  case downloading(receivedBytes: Int64, totalBytes: Int64)
  case completed(OfflineChartDownload)
  case failed(errorMessage: String)
  case cancelled
}

/// Observable ViewModel managing the end-to-end GeoGarage offline chart downloading pipeline,
/// camera viewport extraction, layer selection, download progress observation, and cancellation.
@Observable
@MainActor
final class GeoGarageOfflineViewModel {

  // MARK: - Injected Dependencies

  private let downloader: GeoGarageChartDownloaderProtocol
  private let packageService: GeoGaragePackageServiceProtocol
  private let downloadRepository: GeoGarageDownloadRepositoryProtocol
  private let preferencesService: PreferencesServiceProtocol
  let chartViewModel: ChartViewModel

  // MARK: - State Properties

  var downloadPhase: GeoGarageDownloadPhaseState = .idle
  var selectedLayerID: String = ""
  var zoomMin: Int = 0
  var zoomMax: Int = 14
  var customName: String = ""

  @ObservationIgnored
  private var currentTask: Task<Void, Never>?

  // MARK: - Computed Properties

  var downloadedCharts: [OfflineChartDownload] {
    downloadRepository.downloads
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
    chartViewModel: ChartViewModel
  ) {
    self.downloader = downloader
    self.packageService = packageService
    self.downloadRepository = downloadRepository
    self.preferencesService = preferencesService
    self.chartViewModel = chartViewModel

    if let firstLayer = chartViewModel.availableGeoGarageLayers.first {
      self.selectedLayerID = firstLayer.layer
    }
  }

  // MARK: - Download Actions

  /// Initiates an offline chart package generation and download using the currently displayed map viewport.
  /// - Parameters:
  ///   - apiKey: Dedicated CAAS API key (or OAuth token).
  ///   - customerID: User's GeoGarage customer identifier.
  func startDownload(apiKey: String, customerID: String) {
    guard !isDownloading else { return }

    guard let bounds = chartViewModel.currentVisibleBounds else {
      downloadPhase = .failed(errorMessage: String(localized: "No visible map viewport found. Pan or zoom the chart first."))
      return
    }

    let layerToDownload = selectedLayerID.isEmpty ? (availableLayers.first?.layer ?? "shom") : selectedLayerID
    let selectedLayer = availableLayers.first(where: { $0.layer == layerToDownload })
    let layerName = selectedLayer?.brandName ?? layerToDownload.uppercased()
    let zoneWKT = bounds.toWKT()

    let request = PackageRequest(
      layerID: layerToDownload,
      zoneWKT: zoneWKT,
      zoomMax: zoomMax,
      format: .mbtiles,
      cipher: .v4
    )

    downloadPhase = .requesting
    currentTask?.cancel()

    currentTask = Task { [weak self] in
      guard let self else { return }

      do {
        // 1. Request package generation on the CAAS backend
        let packageID = try await self.packageService.requestPackage(
          request,
          apiKey: apiKey,
          userID: customerID
        )

        var finalStatus: PackageStatusResponse?

        // 2. Poll generation status until completed
        let statusStream = await self.packageService.pollUntilComplete(
          packageID: packageID,
          apiKey: apiKey,
          interval: .seconds(2),
          timeout: .seconds(600)
        )

        for try await status in statusStream {
          if Task.isCancelled {
            self.downloadPhase = .cancelled
            return
          }

          let progress = status.normalizedProgress
          let msg: String
          if let monitor = status.monitor {
            msg = "\(status.state.rawValue): \(monitor)"
          } else {
            msg = status.state.rawValue
          }
          self.downloadPhase = .generating(progress: progress, message: msg)

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

        // 3. Download, validate streaming MD5, and persist
        let totalBytes = completedStatus.size ?? 0
        self.downloadPhase = .downloading(receivedBytes: 0, totalBytes: totalBytes)

        let record = try await self.downloader.download(
          packageID: packageID,
          downloadURL: downloadURL,
          expectedMD5: fileHash,
          layerID: layerToDownload,
          layerName: layerName,
          boundsWKT: zoneWKT,
          zoomMax: self.zoomMax,
          apiKey: apiKey
        )

        self.downloadPhase = .completed(record)
      } catch is CancellationError {
        self.downloadPhase = .cancelled
      } catch let caasError as CaasError {
        self.downloadPhase = .failed(errorMessage: caasError.localizedDescription)
      } catch {
        self.downloadPhase = .failed(errorMessage: error.localizedDescription)
      }
    }
  }

  /// Cancels any in-flight download task and resets state.
  func cancelDownload() {
    currentTask?.cancel()
    currentTask = nil
    downloadPhase = .cancelled
  }

  /// Deletes a previously downloaded offline chart from disk and repository.
  /// - Parameter download: Record to delete.
  func deleteDownload(_ download: OfflineChartDownload) async {
    do {
      try await downloader.deleteLocalChart(id: download.id)
    } catch {
      Logger.caas.error("Failed to delete local chart \(download.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Activates the selected offline chart on the main map.
  /// - Parameters:
  ///   - download: Offline chart record.
  ///   - sharedSecret: Partner secret.
  ///   - customerID: User customer ID.
  func activateDownload(
    _ download: OfflineChartDownload,
    sharedSecret: String,
    customerID: String
  ) async throws(CaasError) {
    try await chartViewModel.switchToDownloadedCaasChart(
      download: download,
      sharedSecret: sharedSecret,
      customerID: customerID
    )
  }
}
