//
//  MBTilesDownloadWorker.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import GRDB
import OSLog

/// Real-time download progress report strictly typed to physical domain measurements.
nonisolated public struct MBTilesDownloadProgress: Sendable, Equatable {
  public let completedTiles: Int
  public let totalTiles: Int
  public let writtenBytes: Measurement<UnitInformationStorage>
  public let percentage: Double

  public init(
    completedTiles: Int,
    totalTiles: Int,
    writtenBytes: Measurement<UnitInformationStorage>,
    percentage: Double
  ) {
    self.completedTiles = completedTiles
    self.totalTiles = totalTiles
    self.writtenBytes = writtenBytes
    self.percentage = percentage
  }
}

nonisolated public enum MBTilesWorkerError: LocalizedError, Sendable {
  case cancelled
  case invalidDestination
  case databaseFailure(String)

  public var errorDescription: String? {
    switch self {
    case .cancelled:
      return String(localized: "Download cancelled by user.")
    case .invalidDestination:
      return String(localized: "Invalid destination file path.")
    case .databaseFailure(let message):
      return String(localized: "MBTiles SQLite failure: \(message)")
    }
  }
}

/// A thread-safe, isolated Swift 6 `actor` responsible for orchestrating MBTiles 1.3 SQLite databases,
/// tile coordinate pyramid calculations, resume checks, and transactional batch writing using GRDB.
///
/// **Data-Agnostic Design:**
/// This worker knows nothing about raster composition or OpenSeaMap specifics. It delegates all fetching
/// to a `TileFetchPipeline`, enabling seamless support for vector tiles (MVT/PBF) or alternative raster sources.
public actor MBTilesDownloadWorker {

  private struct TileKey: Hashable {
    let zoom: Int
    let column: Int
    let row: Int
  }

  private struct BufferedTile: Sendable {
    let zoom: Int
    let column: Int
    let row: Int
    let data: Data
  }

  /// Maximum concurrent HTTP fetch operations permitted across the worker.
  private let maxConcurrentFetches: Int = 2

  /// Number of tiles committed per SQLite write transaction to optimize disk I/O.
  private let batchSize: Int = 50

  /// Throttle interval between consecutive progress notifications to prevent MainActor saturations.
  private let progressThrottleInterval: Duration = .milliseconds(200)

  private var isCancelled: Bool = false
  private var databaseQueue: DatabaseQueue?
  private var accumulatedBytes: Int64 = 0
  private var lastProgressReportInstant: ContinuousClock.Instant = .now - .seconds(10)

  public init() {}

  /// Cancels any active download operation cooperatively.
  public func cancel() {
    isCancelled = true
  }

  /// Executes or resumes an offline MBTiles chart download.
  ///
  /// - Parameters:
  ///   - bounds: The geographic bounding box to cover.
  ///   - minZoom: Minimum zoom level.
  ///   - maxZoom: Maximum zoom level (capped at 15 for OpenSeaMap/OSM).
  ///   - destinationURL: Target `.mbtiles` file URL in `Documents/Charts/`.
  ///   - regionName: Human-readable chart package name.
  ///   - pipeline: Data retrieval pipeline (raster or vector).
  ///   - progressHandler: Real-time progress callback emitting `MBTilesDownloadProgress`.
  public func executeDownload(
    bounds: GeographicBoundingBox,
    minZoom: Int,
    maxZoom: Int,
    destinationURL: URL,
    regionName: String,
    pipeline: any TileFetchPipeline,
    progressHandler: (@Sendable (MBTilesDownloadProgress) -> Void)? = nil
  ) async throws {
    isCancelled = false
    accumulatedBytes = 0
    lastProgressReportInstant = .now - .seconds(10)

    guard destinationURL.isFileURL else {
      throw MBTilesWorkerError.invalidDestination
    }

    // 1. Initialize destination directory and GRDB DatabaseQueue
    let directory = destinationURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var config = Configuration()
    config.qos = .userInitiated
    let dbQueue = try DatabaseQueue(path: destinationURL.path, configuration: config)
    self.databaseQueue = dbQueue
    defer {
      self.databaseQueue = nil
    }

    // 2. Provision standard MBTiles 1.3 SQLite Schema
    try await initializeMBTilesSchema(
      dbQueue: dbQueue,
      regionName: regionName,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      format: pipeline.format
    )

    // 3. Resumability: Inspect existing tiles in database to avoid duplicate downloads
    let existingKeys = try await fetchExistingTileKeys(dbQueue: dbQueue)
    let allCoordinates = MBTilesCoordinateMath.allTileCoordinates(for: bounds, minZoom: minZoom, maxZoom: maxZoom)
    let totalExpectedTiles = allCoordinates.count

    // Filter to retain only missing coordinates with valid TMS conversions
    let missingCoordinates = allCoordinates.filter { coord in
      guard let tms = coord.tmsRow else { return false }
      let key = TileKey(zoom: coord.zoom, column: coord.x, row: tms)
      return !existingKeys.contains(key)
    }

    Logger.offline.info("MBTiles '\(regionName, privacy: .public)': Total \(totalExpectedTiles, privacy: .public) tiles, existing \(existingKeys.count, privacy: .public), remaining to download: \(missingCoordinates.count, privacy: .public)")

    var completedTilesCount = totalExpectedTiles - missingCoordinates.count
    reportProgress(
      completedCount: completedTilesCount,
      totalCount: totalExpectedTiles,
      force: true,
      handler: progressHandler
    )

    if missingCoordinates.isEmpty {
      Logger.offline.info("MBTiles '\(regionName, privacy: .public)': All tiles already downloaded and verified.")
      return
    }

    // 4. Bounded Concurrency TaskGroup (Strictly 2 concurrent operations)
    var buffer: [BufferedTile] = []
    buffer.reserveCapacity(batchSize)

    try await withThrowingTaskGroup(of: BufferedTile?.self) { group in
      var iterator = missingCoordinates.makeIterator()

      // Seed initial tasks up to max concurrency
      for _ in 0..<min(maxConcurrentFetches, missingCoordinates.count) {
        if let nextCoord = iterator.next() {
          group.addTask { [pipeline] in
            guard !Task.isCancelled else { return nil }
            guard let tms = nextCoord.tmsRow else { return nil }
            guard let data = try await pipeline.fetchTileData(zoom: nextCoord.zoom, x: nextCoord.x, y: nextCoord.y) else {
              return nil
            }
            return BufferedTile(zoom: nextCoord.zoom, column: nextCoord.x, row: tms, data: data)
          }
        }
      }

      // Harvest completed results and schedule new ones
      while let result = try await group.next() {
        if isCancelled || Task.isCancelled {
          group.cancelAll()
          break
        }

        completedTilesCount += 1

        if let tile = result {
          accumulatedBytes += Int64(tile.data.count)
          buffer.append(tile)

          // 5. Batch Writing: Commit 50 tiles per GRDB transaction
          if buffer.count >= batchSize {
            let batchToFlush = buffer
            buffer.removeAll(keepingCapacity: true)
            try await writeBatch(batchToFlush, into: dbQueue)
          }
        }

        // Throttled progress notification
        reportProgress(
          completedCount: completedTilesCount,
          totalCount: totalExpectedTiles,
          force: false,
          handler: progressHandler
        )

        // Schedule next tile
        if let nextCoord = iterator.next() {
          group.addTask { [pipeline] in
            guard !Task.isCancelled else { return nil }
            guard let tms = nextCoord.tmsRow else { return nil }
            guard let data = try await pipeline.fetchTileData(zoom: nextCoord.zoom, x: nextCoord.x, y: nextCoord.y) else {
              return nil
            }
            return BufferedTile(zoom: nextCoord.zoom, column: nextCoord.x, row: tms, data: data)
          }
        }
      }
    }

    // Flush any remaining buffered tiles
    if !buffer.isEmpty {
      try await writeBatch(buffer, into: dbQueue)
      buffer.removeAll()
    }

    // Force final progress report
    reportProgress(
      completedCount: completedTilesCount,
      totalCount: totalExpectedTiles,
      force: true,
      handler: progressHandler
    )

    if isCancelled {
      throw MBTilesWorkerError.cancelled
    }

    Logger.offline.info("MBTiles '\(regionName, privacy: .public)' successfully completed and saved at \(destinationURL.lastPathComponent, privacy: .public)")
  }

  // MARK: - SQLite & GRDB Transactions

  private func initializeMBTilesSchema(
    dbQueue: DatabaseQueue,
    regionName: String,
    bounds: GeographicBoundingBox,
    minZoom: Int,
    maxZoom: Int,
    format: String
  ) async throws {
    try await dbQueue.write { db in
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS metadata (
          name TEXT PRIMARY KEY,
          value TEXT
        );
        CREATE TABLE IF NOT EXISTS tiles (
          zoom_level INTEGER,
          tile_column INTEGER,
          tile_row INTEGER,
          tile_data BLOB,
          PRIMARY KEY (zoom_level, tile_column, tile_row)
        );
        CREATE UNIQUE INDEX IF NOT EXISTS tile_index ON tiles (zoom_level, tile_column, tile_row);
      """)

      let boundsString = "\(bounds.southWest.longitude),\(bounds.southWest.latitude),\(bounds.northEast.longitude),\(bounds.northEast.latitude)"
      let centerString = "\(bounds.center.longitude),\(bounds.center.latitude),\(minZoom)"

      let metadataEntries: [(String, String)] = [
        ("name", regionName),
        ("type", "baselayer"),
        ("version", "1.3"),
        ("description", "Generated by Alcyone Sillage"),
        ("format", format),
        ("bounds", boundsString),
        ("center", centerString),
        ("minzoom", "\(minZoom)"),
        ("maxzoom", "\(maxZoom)")
      ]

      for (key, val) in metadataEntries {
        try db.execute(
          sql: "INSERT OR REPLACE INTO metadata (name, value) VALUES (?, ?)",
          arguments: [key, val]
        )
      }
    }
  }

  private func fetchExistingTileKeys(dbQueue: DatabaseQueue) async throws -> Set<TileKey> {
    try await dbQueue.read { db in
      var keys: Set<TileKey> = []
      let rows = try Row.fetchCursor(db, sql: "SELECT zoom_level, tile_column, tile_row FROM tiles")
      while let row = try rows.next() {
        let zoom: Int = row[0]
        let column: Int = row[1]
        let tileRow: Int = row[2]
        keys.insert(TileKey(zoom: zoom, column: column, row: tileRow))
      }
      return keys
    }
  }

  private func writeBatch(_ batch: [BufferedTile], into dbQueue: DatabaseQueue) async throws {
    guard !batch.isEmpty else { return }
    try await dbQueue.write { db in
      for tile in batch {
        try db.execute(
          sql: "INSERT OR REPLACE INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)",
          arguments: [tile.zoom, tile.column, tile.row, tile.data]
        )
      }
    }
  }

  private func reportProgress(
    completedCount: Int,
    totalCount: Int,
    force: Bool = false,
    handler: (@Sendable (MBTilesDownloadProgress) -> Void)?
  ) {
    guard let handler else { return }

    if !force {
      let now = ContinuousClock.now
      guard now - lastProgressReportInstant >= progressThrottleInterval else { return }
      lastProgressReportInstant = now
    } else {
      lastProgressReportInstant = ContinuousClock.now
    }

    let percentage = totalCount > 0 ? min(1.0, Double(completedCount) / Double(totalCount)) : 0.0
    let storageMeasurement = Measurement<UnitInformationStorage>(value: Double(accumulatedBytes), unit: .bytes)
    let progress = MBTilesDownloadProgress(
      completedTiles: completedCount,
      totalTiles: totalCount,
      writtenBytes: storageMeasurement,
      percentage: percentage
    )

    handler(progress)
  }
}
