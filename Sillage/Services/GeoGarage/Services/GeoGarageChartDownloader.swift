//
//  GeoGarageChartDownloader.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

/// Actor responsible for downloading generated MBTiles archives, performing chunk-based streaming MD5
/// validation (preventing OOM and thread starvation on multi-GB charts), guaranteed temporary file cleanup,
/// remote server cleanup, and local filesystem persistence off the Main Thread.
actor GeoGarageChartDownloader: GeoGarageChartDownloaderProtocol {

  private let packageService: GeoGaragePackageServiceProtocol
  private let downloadRepository: GeoGarageDownloadRepositoryProtocol
  private let session: URLSession
  private let chartsDirectoryURL: URL?

  init(
    packageService: GeoGaragePackageServiceProtocol,
    downloadRepository: GeoGarageDownloadRepositoryProtocol,
    session: URLSession = .shared,
    chartsDirectoryURL: URL? = nil
  ) {
    self.packageService = packageService
    self.downloadRepository = downloadRepository
    self.session = session
    self.chartsDirectoryURL = chartsDirectoryURL
  }

  // MARK: - Download Pipeline

  func download(
    packageID: UUID,
    downloadURL: URL,
    expectedMD5: String,
    layerID: String,
    layerName: String,
    boundsWKT: String,
    zoomMax: Int,
    apiKey: String
  ) async throws(CaasError) -> OfflineChartDownload {
    Logger.caas.info("Initiating download for package \(packageID.uuidString, privacy: .public) from \(downloadURL.absoluteString, privacy: .public)")

    let (tempLocation, response): (URL, URLResponse)
    do {
      (tempLocation, response) = try await session.download(from: downloadURL)
    } catch {
      Logger.caas.error("Download failed for package \(packageID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
      throw CaasError.downloadFailed(underlying: error.localizedDescription)
    }

    // MARK: - Guaranteed Temp File Cleanup
    // Ensures the temporary download file is systematically removed upon success, failure, or cancellation.
    defer {
      if FileManager.default.fileExists(atPath: tempLocation.path) {
        try? FileManager.default.removeItem(at: tempLocation)
        Logger.caas.debug("Cleaned up temporary download file at \(tempLocation.path, privacy: .public)")
      }
    }

    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
      Logger.caas.error("Download server returned unexpected HTTP status \(statusCode, privacy: .public)")
      throw CaasError.downloadFailed(underlying: "Download server returned HTTP status \(statusCode)")
    }

    // 1. Streamed MD5 Validation (1 MB chunks with cooperative Task.yield - zero OOM / UI freeze risk)
    Logger.caas.debug("Validating MD5 checksum in streaming mode for package \(packageID.uuidString, privacy: .public)")
    try await StreamingMD5Validator.validateMD5(for: tempLocation, expectedMD5: expectedMD5)
    Logger.caas.info("MD5 checksum successfully verified for package \(packageID.uuidString, privacy: .public)")

    // 2. Prepare Destination in Documents/Charts/
    let destinationDirectory: URL
    if let customDir = chartsDirectoryURL {
      destinationDirectory = customDir
    } else if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      destinationDirectory = documentsURL.appendingPathComponent("Charts", isDirectory: true)
    } else {
      throw CaasError.fileSystemError(underlying: "Documents directory is inaccessible.")
    }

    if !FileManager.default.fileExists(atPath: destinationDirectory.path) {
      do {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
      } catch {
        throw CaasError.fileSystemError(underlying: "Unable to create Charts directory: \(error.localizedDescription)")
      }
    }

    let fileName = "\(layerID)_\(packageID.uuidString.lowercased()).mbtiles"
    let destinationFileURL = destinationDirectory.appendingPathComponent(fileName)
    let relativePath = "Charts/\(fileName)"

    // Remove existing file at destination if present (e.g. retry)
    if FileManager.default.fileExists(atPath: destinationFileURL.path) {
      try? FileManager.default.removeItem(at: destinationFileURL)
    }

    do {
      try FileManager.default.moveItem(at: tempLocation, to: destinationFileURL)
      Logger.caas.info("Relocated downloaded package to \(destinationFileURL.path, privacy: .public)")
    } catch {
      throw CaasError.fileSystemError(underlying: "Failed to move downloaded file to destination: \(error.localizedDescription)")
    }

    // 3. Delete remote package from CAAS server to free server storage
    do {
      try await packageService.deletePackage(packageID: packageID, apiKey: apiKey)
      Logger.caas.info("Deleted remote package \(packageID.uuidString, privacy: .public) on CAAS server.")
    } catch {
      Logger.caas.warning("Failed to delete remote package on CAAS server (non-fatal): \(error.localizedDescription, privacy: .public)")
    }

    // 4. Register download record in repository on MainActor
    let record = OfflineChartDownload(
      id: packageID,
      layerID: layerID,
      layerName: layerName,
      downloadDate: Date(),
      relativePath: relativePath,
      md5: expectedMD5.lowercased(),
      zoomMax: zoomMax,
      boundsWKT: boundsWKT
    )

    await downloadRepository.save(record)
    Logger.caas.info("Successfully registered download record for package \(packageID.uuidString, privacy: .public)")

    return record
  }

  // MARK: - Delete Local Chart

  func deleteLocalChart(id: UUID) async throws(CaasError) {
    guard let record = await downloadRepository.downloads.first(where: { $0.id == id }) else {
      return
    }

    if let fileURL = record.resolvedFileURL(), FileManager.default.fileExists(atPath: fileURL.path) {
      do {
        try FileManager.default.removeItem(at: fileURL)
        Logger.caas.info("Deleted local MBTiles file at \(fileURL.path, privacy: .public)")
      } catch {
        throw CaasError.fileSystemError(underlying: "Failed to delete local MBTiles file: \(error.localizedDescription)")
      }
    }

    await downloadRepository.delete(id: id)
  }
}
