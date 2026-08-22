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
import os
import OSLog

/// A thread-safe, persistent service responsible for downloading generated MBTiles archives via
/// iOS native background `URLSession` (`URLSessionDownloadTask`), performing chunk-based streaming MD5
/// validation, guaranteed temporary file cleanup, remote CAAS server cleanup, and local filesystem persistence.
final class GeoGarageChartDownloader: NSObject, GeoGarageChartDownloaderProtocol, URLSessionDownloadDelegate, @unchecked Sendable {

  static let backgroundSessionIdentifier = "com.alcyone.sillage.geogaragedownloads"

  private struct ActiveTaskContext {
    let progressHandler: (@Sendable (Int64, Int64) -> Void)?
    var continuation: CheckedContinuation<URL, Error>?
  }

  private let packageService: GeoGaragePackageServiceProtocol
  private let downloadRepository: GeoGarageDownloadRepositoryProtocol
  private let chartsDirectoryURL: URL?
  private var session: URLSession!

  private let tasksLock = OSAllocatedUnfairLock<[Int: ActiveTaskContext]>(initialState: [:])
  private let backgroundCompletionHandlerLock = OSAllocatedUnfairLock<(() -> Void)?>(initialState: nil)

  init(
    packageService: GeoGaragePackageServiceProtocol,
    downloadRepository: GeoGarageDownloadRepositoryProtocol,
    sessionConfiguration: URLSessionConfiguration? = nil,
    chartsDirectoryURL: URL? = nil
  ) {
    self.packageService = packageService
    self.downloadRepository = downloadRepository
    self.chartsDirectoryURL = chartsDirectoryURL
    super.init()

    let config: URLSessionConfiguration
    if let sessionConfiguration {
      config = sessionConfiguration
    } else {
      config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
      config.isDiscretionary = false
      config.sessionSendsLaunchEvents = true
      config.waitsForConnectivity = true
    }

    let queue = OperationQueue()
    queue.name = "com.alcyone.sillage.geogaragedownloader.queue"
    queue.maxConcurrentOperationCount = 2
    self.session = URLSession(configuration: config, delegate: self, delegateQueue: queue)

    // Technical Design: Cancel any pre-existing orphan tasks from previous OS sessions so that we start with a clean slate
    self.session.getAllTasks { tasks in
      for task in tasks {
        Logger.caas.info("Cancelling orphaned background download task \(task.taskIdentifier, privacy: .public) on startup")
        task.cancel()
      }
    }
  }

  // MARK: - Background URLSession Completion Handling

  func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
    backgroundCompletionHandlerLock.withLock {
      $0 = handler
    }
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
    apiKey: String,
    localID: UUID? = nil,
    progressHandler: (@Sendable (Int64, Int64) -> Void)? = nil
  ) async throws(CaasError) -> OfflineChartDownload {
    Logger.caas.info("Initiating background download for package \(packageID.uuidString, privacy: .public) from \(downloadURL.absoluteString, privacy: .public)")

    let downloadTask = session.downloadTask(with: downloadURL)
    let taskID = downloadTask.taskIdentifier

    let stagedTempLocation: URL
    do {
      stagedTempLocation = try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          tasksLock.withLock {
            $0[taskID] = ActiveTaskContext(
              progressHandler: progressHandler,
              continuation: continuation
            )
          }
          downloadTask.resume()
        }
      } onCancel: {
        downloadTask.cancel()
      }
    } catch {
      tasksLock.withLock { _ = $0.removeValue(forKey: taskID) }
      Logger.caas.error("Download failed for package \(packageID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
      throw CaasError.downloadFailed(underlying: error.localizedDescription)
    }

    // Guaranteed cleanup of the staged file
    defer {
      if FileManager.default.fileExists(atPath: stagedTempLocation.path) {
        try? FileManager.default.removeItem(at: stagedTempLocation)
        Logger.caas.debug("Cleaned up staged temporary download file at \(stagedTempLocation.path, privacy: .public)")
      }
    }

    // 1. Streamed MD5 Validation (1 MB chunks with cooperative Task.yield - zero OOM / UI freeze risk)
    Logger.caas.debug("Validating MD5 checksum in streaming mode for package \(packageID.uuidString, privacy: .public)")
    try await StreamingMD5Validator.validateMD5(for: stagedTempLocation, expectedMD5: expectedMD5)
    Logger.caas.info("MD5 checksum successfully verified for package \(packageID.uuidString, privacy: .public)")

    // 2. Prepare Destination in Documents/GeoGarage/
    let destinationDirectory: URL
    if let customDir = chartsDirectoryURL {
      destinationDirectory = customDir
    } else if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      destinationDirectory = documentsURL.appendingPathComponent("GeoGarage", isDirectory: true)
    } else {
      throw CaasError.fileSystemError(underlying: "Documents directory is inaccessible.")
    }

    if !FileManager.default.fileExists(atPath: destinationDirectory.path) {
      do {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
      } catch {
        throw CaasError.fileSystemError(underlying: "Unable to create GeoGarage directory: \(error.localizedDescription)")
      }
    }

    let recordID = localID ?? packageID
    let fileName = "\(layerID)_\(recordID.uuidString.lowercased()).mbtiles"
    let destinationFileURL = destinationDirectory.appendingPathComponent(fileName)
    let relativePath = "GeoGarage/\(fileName)"

    // Remove existing file at destination if present (e.g. retry)
    if FileManager.default.fileExists(atPath: destinationFileURL.path) {
      try? FileManager.default.removeItem(at: destinationFileURL)
    }

    do {
      try FileManager.default.moveItem(at: stagedTempLocation, to: destinationFileURL)
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

    // 4. Register download record in repository
    let record = OfflineChartDownload(
      id: recordID,
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
    let targetRecord = await MainActor.run {
      downloadRepository.downloads.first(where: { $0.id == id })
    }
    guard let record = targetRecord else {
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

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    let taskID = downloadTask.taskIdentifier
    let handler = tasksLock.withLock { $0[taskID]?.progressHandler }
    handler?(totalBytesWritten, totalBytesExpectedToWrite)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let taskID = downloadTask.taskIdentifier

    // Apple requirement: The file at `location` will be deleted immediately after this method returns.
    // We must move it synchronously to a temporary staged file.
    let stagedURL = FileManager.default.temporaryDirectory.appendingPathComponent("caas_\(UUID().uuidString).mbtiles")
    do {
      if FileManager.default.fileExists(atPath: stagedURL.path) {
        try FileManager.default.removeItem(at: stagedURL)
      }
      try FileManager.default.moveItem(at: location, to: stagedURL)

      let continuation = tasksLock.withLock { $0.removeValue(forKey: taskID)?.continuation }
      continuation?.resume(returning: stagedURL)
    } catch {
      let continuation = tasksLock.withLock { $0.removeValue(forKey: taskID)?.continuation }
      continuation?.resume(throwing: error)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    let taskID = task.taskIdentifier
    let continuation = tasksLock.withLock { $0.removeValue(forKey: taskID)?.continuation }
    continuation?.resume(throwing: error)
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    Logger.caas.info("All background URLSession events finished for session \(session.configuration.identifier ?? "default", privacy: .public)")
    let handler = backgroundCompletionHandlerLock.withLock {
      let current = $0
      $0 = nil
      return current
    }
    if let handler {
      DispatchQueue.main.async {
        Logger.caas.info("Invoking background URLSession completion handler on Main thread")
        handler()
      }
    }
  }
}
