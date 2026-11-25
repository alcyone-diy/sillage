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

    // Fail-safe storage guard before any network request: never purge an existing valid chart upfront
    // to make room, because the replacement download may fail or lose connectivity at sea.
    let estimatedSize = OfflinePackageSizeEstimator.estimatePackageSize(
      wkt: item.boundsWKT,
      zoomMax: item.zoomMax
    )
    try verifySufficientDiskSpace(for: estimatedSize, stage: "pre-request")

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
      accessToken: accessToken,
      onEvent: onEvent,
      onProgress: onProgress
    )
  }

  // MARK: - Private Pipeline Steps

  /// Enforces a blocking, fail-safe disk space check before starting server generation or archive download.
  /// Throws `CaasError.diskSpaceUnavailable` when available device space cannot be read,
  /// and `CaasError.insufficientDiskSpace` when free space is below the required threshold
  /// (falling back to `minimumDeviceFreeBuffer` when package size is indeterminate).
  private func verifySufficientDiskSpace(
    for downloadSize: Measurement<UnitInformationStorage>?,
    stage: String
  ) throws(CaasError) {
    guard let available = diskSpaceProvider.availableDiskSpace() else {
      Logger.offline.warning("Unable to read available disk space (\(stage, privacy: .public)). Aborting download fail-safely.")
      throw .diskSpaceUnavailable
    }

    let required: Measurement<UnitInformationStorage>
    if let downloadSize {
      required = OfflineStoragePolicy.requiredSpace(forDownloadSize: downloadSize)
    } else {
      Logger.offline.warning("Download size unavailable (\(stage, privacy: .public)); enforcing minimum device free buffer.")
      required = OfflineStoragePolicy.minimumDeviceFreeBuffer
    }

    if available < required {
      Logger.offline.warning("Insufficient disk space for offline chart download (\(stage, privacy: .public); available: \(available.converted(to: .megabytes).value, privacy: .public) MB, required: \(required.converted(to: .megabytes).value, privacy: .public) MB). Aborting without deleting existing charts.")
      throw .insufficientDiskSpace(required: required, available: available)
    }
  }

  private func pollAndDownloadArchive(
    packageID: UUID,
    item: PendingCAASDownload,
    accessToken: String,
    onEvent: @Sendable (GeoGarageDownloadPipelineEvent) async -> Void,
    onProgress: @escaping @Sendable (Int64, Int64) -> Void
  ) async throws -> OfflineChartDownload {
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

    // Re-evaluate disk space with the exact server-reported archive size before starting the transfer
    // (or enforce minimumDeviceFreeBuffer if the server omitted `size`).
    let exactPackageSize = totalBytes > 0
      ? Measurement(value: Double(totalBytes), unit: UnitInformationStorage.bytes)
      : nil
    try verifySufficientDiskSpace(for: exactPackageSize, stage: "pre-download")

    await onEvent(.downloadingStarted(totalBytes: totalBytes))

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

    // Post-download replacement cleanup is strictly non-fatal: never invalidate an already verified local archive,
    // and only remove the replaced chart after the new archive has passed MD5 verification and been persisted.
    if let replacesID = item.replacesChartID {
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
