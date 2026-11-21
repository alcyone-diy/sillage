//
//  ChartStorageService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

public enum ChartStorageError: Error, LocalizedError, Sendable {
  case documentsDirectoryNotFound
  case securityAccessFailed
  case copyFailed(String)

  public var errorDescription: String? {
    switch self {
    case .documentsDirectoryNotFound:
      return String(localized: "Documents directory not found.")
    case .securityAccessFailed:
      return String(localized: "Failed to access the file securely.")
    case .copyFailed(let message):
      return String(localized: "Failed to copy the file: \(message)")
    }
  }
}

public actor ChartStorageService {
  public init() {}

  private func resolveChartsDirectory(fileManager: FileManager = .default) throws -> (documents: URL, charts: URL) {
    guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
      throw ChartStorageError.documentsDirectoryNotFound
    }
    let chartsDirectory = documentsDirectory.appendingPathComponent("Charts")
    try fileManager.createDirectory(at: chartsDirectory, withIntermediateDirectories: true, attributes: nil)
    return (documentsDirectory, chartsDirectory)
  }

  /// Migrates any legacy `.mbtiles` files placed directly in `Documents/` into `Documents/Charts/`.
  private func migrateLegacyRootMBTiles(from documentsDirectory: URL, to chartsDirectory: URL, fileManager: FileManager) {
    guard let rootFiles = try? fileManager.contentsOfDirectory(
      at: documentsDirectory,
      includingPropertiesForKeys: nil,
      options: .skipsHiddenFiles
    ) else { return }

    for fileURL in rootFiles where fileURL.pathExtension.lowercased() == "mbtiles" {
      let destinationURL = uniqueDestinationURL(for: fileURL, in: chartsDirectory, fileManager: fileManager)
      do {
        try fileManager.moveItem(at: fileURL, to: destinationURL)
        Logger.storage.info("Migrated legacy MBTiles from Documents root to \(destinationURL.lastPathComponent, privacy: .public)")
      } catch {
        Logger.storage.error("Failed to migrate legacy MBTiles \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func uniqueDestinationURL(for sourceURL: URL, in directory: URL, fileManager: FileManager) -> URL {
    let originalFileName = sourceURL.lastPathComponent
    var destinationURL = directory.appendingPathComponent(originalFileName)

    var fileCount = 1
    let nameWithoutExtension = sourceURL.deletingPathExtension().lastPathComponent
    let fileExtension = sourceURL.pathExtension

    while fileManager.fileExists(atPath: destinationURL.path) {
      let newFileName = "\(nameWithoutExtension)_\(fileCount).\(fileExtension)"
      destinationURL = directory.appendingPathComponent(newFileName)
      fileCount += 1
    }

    return destinationURL
  }

  /// Imports an external `.mbtiles` file into `Documents/Charts/` by copying it safely.
  public func importChart(from sourceURL: URL) throws -> URL {
    let fileManager = FileManager.default
    let isSecurityScoped = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if isSecurityScoped {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    // Security-scoped access is optional for local sandbox URLs, required for external file providers.
    if !isSecurityScoped && !fileManager.isReadableFile(atPath: sourceURL.path) {
      throw ChartStorageError.securityAccessFailed
    }

    let (_, chartsDirectory) = try resolveChartsDirectory(fileManager: fileManager)
    let destinationURL = uniqueDestinationURL(for: sourceURL, in: chartsDirectory, fileManager: fileManager)
    let tempURL = chartsDirectory.appendingPathComponent(".\(UUID().uuidString).tmp")

    do {
      try fileManager.copyItem(at: sourceURL, to: tempURL)
      try fileManager.moveItem(at: tempURL, to: destinationURL)
      return destinationURL
    } catch {
      if fileManager.fileExists(atPath: tempURL.path) {
        try? fileManager.removeItem(at: tempURL)
      }
      throw ChartStorageError.copyFailed(error.localizedDescription)
    }
  }

  /// Discovers MBTiles files located in the app's Documents/Charts directory.
  /// - Returns: An array of `MBTileFile` containing file metadata.
  /// - Throws: An error if the documents directory cannot be accessed or if reading fails.
  public func discoverMBTiles() async throws -> [MBTileFile] {
    let fileManager = FileManager.default
    let (documentsDirectory, chartsDirectory) = try resolveChartsDirectory(fileManager: fileManager)

    migrateLegacyRootMBTiles(from: documentsDirectory, to: chartsDirectory, fileManager: fileManager)

    // Fetch directory contents, pre-fetching file size attributes to optimize disk I/O.
    let files = try fileManager.contentsOfDirectory(at: chartsDirectory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
    
    return files.compactMap { fileURL in
      // Filter only .mbtiles files
      guard fileURL.pathExtension.lowercased() == "mbtiles" else { return nil }

      // Validate standard unencrypted SQLite header (first 16 bytes: "SQLite format 3\0")
      // Encrypted SQLCipher files will not match this header and must not be loaded via mbtiles://
      guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
      let header = (try? handle.read(upToCount: 16)) ?? Data()
      try? handle.close()
      guard header == Data("SQLite format 3\0".utf8) else { return nil }
      
      var fileSizeMeasurement: Measurement<UnitInformationStorage>? = nil
      
      // Retrieve the pre-fetched file size
      if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
         let fileSizeInBytes = resourceValues.fileSize {
        fileSizeMeasurement = Measurement(value: Double(fileSizeInBytes), unit: .bytes)
      }
      
      return MBTileFile(filename: fileURL.lastPathComponent, fileURL: fileURL, fileSize: fileSizeMeasurement)
    }
  }

  /// Creates an asynchronous stream that emits the list of MBTiles files whenever the directory changes.
  /// - Returns: An `AsyncStream` yielding arrays of `MBTileFile`.
  nonisolated public func observeMBTilesDirectory() -> AsyncStream<[MBTileFile]> {
    AsyncStream { continuation in
      guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        continuation.finish()
        return
      }
      
      let chartsDirectory = documentsDirectory.appendingPathComponent("Charts")
      
      // Ensure the directory exists before observing it.
      try? FileManager.default.createDirectory(at: chartsDirectory, withIntermediateDirectories: true, attributes: nil)
      
      // Open a read-only file descriptor to monitor directory events.
      let fileDescriptor = open(chartsDirectory.path, O_EVTONLY)
      guard fileDescriptor != -1 else {
        continuation.finish()
        return
      }
      
      // Create a dispatch source to monitor file system writes (additions, deletions, modifications).
      let dispatchSource = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fileDescriptor,
        eventMask: .write,
        queue: DispatchQueue.global(qos: .background)
      )
      
      // Define the handler triggered on directory changes.
      dispatchSource.setEventHandler { [weak self] in
        Task { [weak self] in
          guard let self else { return }
          do {
            let updatedFiles = try await self.discoverMBTiles()
            continuation.yield(updatedFiles)
          } catch {
            Logger.storage.error("Error reading files during observation: \(error.localizedDescription, privacy: .public)")
          }
        }
      }
      
      // IMPORTANT: Close the file descriptor when the observer is cancelled to prevent memory/resource leaks.
      dispatchSource.setCancelHandler {
        close(fileDescriptor)
      }
      
      // Handle cancellation from the consumer side (e.g., when the UI view disappears).
      continuation.onTermination = { @Sendable _ in
        dispatchSource.cancel()
      }
      
      // Start the observer.
      dispatchSource.resume()
      
      // Emit the initial state immediately.
      Task { [weak self] in
        guard let self else { return }
        if let initialFiles = try? await self.discoverMBTiles() {
          continuation.yield(initialFiles)
        }
      }
    }
  }
}
