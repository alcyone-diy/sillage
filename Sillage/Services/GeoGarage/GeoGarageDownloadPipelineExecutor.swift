//
//  GeoGarageDownloadPipelineExecutor.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

/// Intermediate lifecycle milestones and persistence mutations emitted during a single CAAS chart
/// download execution. Terminal outcomes are communicated strictly via return value or `throws`.
nonisolated enum GeoGarageDownloadPipelineEvent: Equatable, Sendable {
  /// Indicates that the previously retained local chart was deleted upfront due to constrained disk space,
  /// requiring `replacesChartID` to be cleared immediately in persistent pending state.
  case replacesChartCleared

  /// Indicates that the CAAS server assigned a `packageID`, which must be persisted immediately
  /// before polling begins so interrupted sessions can resume without re-requesting generation.
  case packageIDAssigned(UUID)

  /// Reports server-side tile generation progress and status description during polling.
  case generating(progress: Double?, message: String)

  /// Indicates that server generation succeeded and archive transfer is starting with known byte size.
  case downloadingStarted(totalBytes: Int64)
}

/// Stateless, `Sendable` unit executor responsible for running a single CAAS chart package
/// generation, polling, archive download, custom naming, and replacement cleanup pipeline.
///
/// Queue orchestration, `@Observable` UI state, 4 Hz progress throttling, connectivity classification,
/// and `PreferencesService` persistence remain exclusively owned by `GeoGarageDownloadService`.
nonisolated struct GeoGarageDownloadPipelineExecutor: Sendable {

  private let packageService: GeoGaragePackageServiceProtocol
  private let downloader: GeoGarageChartDownloaderProtocol
  private let downloadRepository: GeoGarageDownloadRepositoryProtocol
  private let diskSpaceProvider: DiskSpaceProviderProtocol

  init(
    packageService: GeoGaragePackageServiceProtocol,
    downloader: GeoGarageChartDownloaderProtocol,
    downloadRepository: GeoGarageDownloadRepositoryProtocol,
    diskSpaceProvider: DiskSpaceProviderProtocol
  ) {
    self.packageService = packageService
    self.downloader = downloader
    self.downloadRepository = downloadRepository
    self.diskSpaceProvider = diskSpaceProvider
  }

  /// Executes the full unitary download pipeline for `item`.
  ///
  /// - Parameters:
  ///   - item: Immutable snapshot of the pending download job at execution start.
  ///   - accessToken: Validated OAuth2 bearer token for GeoGarage CAAS endpoints.
  ///   - onEvent: Asynchronous callback invoked for intermediate phase transitions and state mutations
  ///     that must be persisted before advancing to the next network step.
  ///   - onProgress: Synchronous byte-progress callback forwarded directly from the archive downloader.
  /// - Returns: The finalized `OfflineChartDownload` record stored locally.
  func execute(
    item: PendingCAASDownload,
    accessToken: String,
    onEvent: @Sendable (GeoGarageDownloadPipelineEvent) async -> Void,
    onProgress: @escaping @Sendable (Int64, Int64) -> Void
  ) async throws -> OfflineChartDownload {
    try Task.checkCancellation()

    guard !accessToken.isEmpty else {
      throw CaasError.authenticationRequired
    }

    var currentReplacesChartID = item.replacesChartID

    // Storage safety evaluation before package generation request when replacing an existing chart:
    // retain the valid local chart unless constrained disk space forces upfront removal.
    if let replacesID = currentReplacesChartID {
      let estimatedSize = OfflinePackageSizeEstimator.estimatePackageSize(
        wkt: item.boundsWKT,
        zoomMax: item.zoomMax
      )
      let available = diskSpaceProvider.availableDiskSpace()
      let hasSufficientSpace: Bool
      if let estimatedSize, let available {
        hasSufficientSpace = OfflineStoragePolicy.hasSufficientSpace(
          availableSpace: available,
          estimatedDownloadSize: estimatedSize
        )
      } else {
        hasSufficientSpace = false
      }

      if !hasSufficientSpace {
        Logger.offline.warning("Insufficient storage buffer to retain chart \(replacesID.uuidString, privacy: .public). Deleting upfront before download.")
        do {
          try await downloader.deleteLocalChart(id: replacesID)
          currentReplacesChartID = nil
          await onEvent(.replacesChartCleared)
          Logger.offline.info("Deleted previous chart \(replacesID.uuidString, privacy: .public) upfront due to storage limits.")
        } catch {
          Logger.offline.error("Failed to delete previous chart upfront: \(error.localizedDescription, privacy: .public)")
          throw error
        }
      } else {
        Logger.offline.info("Sufficient storage space available. Retaining previous chart \(replacesID.uuidString, privacy: .public) during download.")
      }
    }

    try Task.checkCancellation()

    let packageID: UUID
    if let existing = item.packageID {
      packageID = existing
    } else {
      let request = PackageRequest(
        layerID: item.layerID,
        zoneWKT: item.boundsWKT,
        zoomMax: item.zoomMax,
        format: .mbtiles,
        cipher: .v4
      )

      packageID = try await packageService.requestPackage(
        request,
        accessToken: accessToken
      )

      try Task.checkCancellation()
      await onEvent(.packageIDAssigned(packageID))
    }

    try Task.checkCancellation()

    return try await pollAndDownloadArchive(
      packageID: packageID,
      item: item,
      currentReplacesChartID: currentReplacesChartID,
      accessToken: accessToken,
      onEvent: onEvent,
      onProgress: onProgress
    )
  }

  // MARK: - Private Pipeline Steps

  private func pollAndDownloadArchive(
    packageID: UUID,
    item: PendingCAASDownload,
    currentReplacesChartID: UUID?,
    accessToken: String,
    onEvent: @Sendable (GeoGarageDownloadPipelineEvent) async -> Void,
    onProgress: @escaping @Sendable (Int64, Int64) -> Void
  ) async throws -> OfflineChartDownload {
    var retainedReplacesChartID = currentReplacesChartID
    var finalStatus: PackageStatusResponse?

    let statusStream = await packageService.pollUntilComplete(
      packageID: packageID,
      accessToken: accessToken
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
      await onEvent(.generating(progress: progress, message: msg))

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
    await onEvent(.downloadingStarted(totalBytes: totalBytes))

    // Storage re-evaluation before downloading the archive file using exact server-reported byte size.
    // Non-fatal if deletion fails here: retainedReplacesChartID stays set so post-download cleanup retries.
    if let replacesID = retainedReplacesChartID, totalBytes > 0 {
      let exactPackageSize = Measurement(value: Double(totalBytes), unit: UnitInformationStorage.bytes)
      let available = diskSpaceProvider.availableDiskSpace()
      let hasSufficientSpace = available.map {
        OfflineStoragePolicy.hasSufficientSpace(
          availableSpace: $0,
          estimatedDownloadSize: exactPackageSize
        )
      } ?? false

      if !hasSufficientSpace {
        Logger.offline.warning("Storage became constrained during package generation for \(replacesID.uuidString, privacy: .public). Deleting old chart now before archive download.")
        do {
          try await downloader.deleteLocalChart(id: replacesID)
          retainedReplacesChartID = nil
          await onEvent(.replacesChartCleared)
        } catch {
          Logger.offline.error("Failed to delete old chart before archive download: \(error.localizedDescription, privacy: .public)")
        }
      }
    }

    try Task.checkCancellation()

    let record = try await downloader.download(
      packageID: packageID,
      downloadURL: downloadURL,
      expectedMD5: fileHash,
      layerID: item.layerID,
      layerName: item.layerName,
      boundsWKT: item.boundsWKT,
      zoomMax: item.zoomMax,
      accessToken: accessToken,
      localID: item.id,
      progressHandler: onProgress
    )

    let finalRecord: OfflineChartDownload
    if let custom = item.customName, !custom.isEmpty {
      let customRecord = record.updatingCustomName(custom)
      do {
        try await downloadRepository.save(customRecord)
      } catch {
        Logger.offline.warning("Non-fatal: Failed to persist custom name for chart \(item.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
      }
      finalRecord = customRecord
    } else {
      finalRecord = record
    }

    // Post-download replacement cleanup is strictly non-fatal: never invalidate an already verified local archive.
    if let replacesID = retainedReplacesChartID {
      do {
        try await downloader.deleteLocalChart(id: replacesID)
        Logger.offline.info("Deleted previous offline chart package \(replacesID.uuidString, privacy: .public) after successfully replacing zone.")
      } catch {
        Logger.offline.warning("Non-fatal: Failed to delete previous chart package \(replacesID.uuidString, privacy: .public) after replacement: \(error.localizedDescription, privacy: .public)")
      }
    }

    return finalRecord
  }
}
