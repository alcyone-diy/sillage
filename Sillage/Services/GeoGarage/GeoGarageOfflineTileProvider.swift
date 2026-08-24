//
//  GeoGarageOfflineTileProvider.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog
import os

/// High-throughput, concurrent provider for offline GeoGarage MBTiles packages.
///
/// **Concurrency Architecture**:
/// - Reading tiles (`tile(layerID:z:x:y:)`) is completely nonisolated and executed concurrently across threads
///   without actor queuing bottlenecks.
/// - Synchronization of active packages (`reloadDownloads`, `close`) is thread-safe using `OSAllocatedUnfairLock`
///   to atomically update readers mapping without blocking read operations.
final class GeoGarageOfflineTileProvider: GeoGarageOfflineTileProviderProtocol, @unchecked Sendable {

  private struct ReaderEntry: Sendable {
    let downloadID: UUID
    let fileURL: URL
    let reader: any SQLCipherMBTilesReaderProtocol
  }

  /// Lock-protected registry mapping `layerID` to active package readers.
  private let readersLock = OSAllocatedUnfairLock<[String: [ReaderEntry]]>(initialState: [:])

  // MARK: - Initializer

  init() {}

  // MARK: - Tile Retrieval (Concurrent & Non-blocking)

  func tile(layerID: String, z: Int, x: Int, y: Int) async -> Data? {
    guard !layerID.isEmpty, z >= 0, x >= 0, y >= 0 else { return nil }

    let normalizedKey = layerID.lowercased()

    // Fast atomic snapshot of active readers for this layer
    let entries = readersLock.withLock { registry in
      registry[normalizedKey] ?? []
    }

    guard !entries.isEmpty else { return nil }

    // Search across readers
    for entry in entries {
      guard !Task.isCancelled else { return nil }
      if let tileData = await entry.reader.tile(z: z, x: x, y: y), !tileData.isEmpty {
        return tileData
      }
    }

    return nil
  }

  // MARK: - Download Synchronization

  func reloadDownloads(
    _ downloads: [OfflineChartDownload],
    sharedSecret: String,
    customerID: String
  ) async {
    guard !sharedSecret.isEmpty, !customerID.isEmpty else {
      Logger.caas.warning("Cannot reload offline tile readers: missing sharedSecret or customerID.")
      await close()
      return
    }

    let encryptionKey = GeoGarageKeyDeriver.derivePassphrase(sharedSecret: sharedSecret, customerID: customerID)

    // Group downloads by normalized layerID
    var targetDownloadsByLayer: [String: [OfflineChartDownload]] = [:]
    for download in downloads {
      targetDownloadsByLayer[download.layerID.lowercased(), default: []].append(download)
    }

    // Capture existing readers to reuse already opened readers
    let currentRegistry = readersLock.withLock { $0 }
    var newRegistry: [String: [ReaderEntry]] = [:]
    var readersToClose: [any SQLCipherMBTilesReaderProtocol] = []

    for (layerID, layerDownloads) in targetDownloadsByLayer {
      var layerEntries: [ReaderEntry] = []
      let existingLayerEntries = currentRegistry[layerID] ?? []

      for download in layerDownloads {
        guard let fileURL = download.resolvedFileURL(),
              FileManager.default.fileExists(atPath: fileURL.path) else {
          Logger.caas.warning("Offline chart file not found for download \(download.id.uuidString, privacy: .public)")
          continue
        }

        // Reuse existing reader if already opened for this download ID and URL
        if let existing = existingLayerEntries.first(where: { $0.downloadID == download.id && $0.fileURL == fileURL }) {
          layerEntries.append(existing)
        } else {
          do {
            let reader = try SQLCipherMBTilesReader(fileURL: fileURL, encryptionKey: encryptionKey)
            layerEntries.append(ReaderEntry(downloadID: download.id, fileURL: fileURL, reader: reader))
            Logger.caas.info("Opened offline reader for layer \(layerID, privacy: .public) [\(download.layerName, privacy: .public)]")
          } catch {
            Logger.caas.error("Failed to open SQLCipher reader for \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
          }
        }
      }

      if !layerEntries.isEmpty {
        newRegistry[layerID] = layerEntries
      }
    }

    // Determine readers that were removed and need to be closed
    let allNewReaderIDs = Set(newRegistry.values.flatMap { $0 }.map { $0.downloadID })
    for existingEntry in currentRegistry.values.flatMap({ $0 }) {
      if !allNewReaderIDs.contains(existingEntry.downloadID) {
        readersToClose.append(existingEntry.reader)
      }
    }

    // Atomically swap the registry
    let finalRegistry = newRegistry
    readersLock.withLock { registry in
      registry = finalRegistry
    }

    // Close decommissioned readers asynchronously
    for reader in readersToClose {
      await reader.close()
    }

    Logger.caas.info("Reloaded offline tile provider with \(newRegistry.values.reduce(0, { $0 + $1.count }), privacy: .public) active package reader(s).")
  }

  // MARK: - Teardown

  func close() async {
    let readers = readersLock.withLock { registry -> [ReaderEntry] in
      let all = registry.values.flatMap { $0 }
      registry = [:]
      return all
    }

    for entry in readers {
      await entry.reader.close()
    }

    Logger.caas.info("All offline tile readers closed.")
  }
}
