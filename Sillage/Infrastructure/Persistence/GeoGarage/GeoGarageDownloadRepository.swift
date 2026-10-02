//
//  GeoGarageDownloadRepository.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog
import GRDB

// MARK: - Protocol

protocol GeoGarageDownloadRepositoryProtocol: AnyObject, Sendable {
  @MainActor var downloads: [OfflineChartDownload] { get }
  @MainActor func load() async
  @MainActor func save(_ download: OfflineChartDownload) async throws
  @MainActor func delete(id: UUID) async throws
  @MainActor func lastDownloadDate(for layerID: String) -> Date?
  @MainActor func fetchLastDownloadDate(for layerID: String) async throws -> Date?
}

// MARK: - Implementation

/// `@MainActor` repository managing the collection of locally downloaded CAAS MBTiles packages.
///
/// **Architecture**:
/// - Single Responsibility Principle (SRP): pure persistence repository backed by SQLite via `DatabaseManager`.
/// - Observable state (`downloads`) is isolated on `@MainActor` for reactive UI bindings.
/// - Read/Write operations are delegated to `DatabaseManager.reader` and `DatabaseManager.writer`.
/// - Zero dependencies on `FileManager`, `LocalFilePersistenceActor`, or JSON encoders/decoders.
@Observable
@MainActor
final class GeoGarageDownloadRepository: GeoGarageDownloadRepositoryProtocol {
  private(set) var downloads: [OfflineChartDownload] = []

  private let databaseManager: DatabaseManager

  // MARK: - Init

  init(databaseManager: DatabaseManager) {
    self.databaseManager = databaseManager
  }

  // MARK: - Load

  /// Loads downloaded packages from the SQLite database.
  /// Should be called during app bootstrap before accessing `downloads`.
  func load() async {
    do {
      let records = try await databaseManager.reader.read { db in
        try GeoGarageDownloadRecord
          .order(GeoGarageDownloadRecord.Columns.download_timestamp_unix.desc)
          .fetchAll(db)
      }
      self.downloads = records.compactMap { $0.toDomain() }
      Logger.caas.info("Loaded \(self.downloads.count, privacy: .public) offline chart download(s) from database.")
    } catch {
      Logger.caas.error("Failed to load download repository from database: \(error, privacy: .public)")
      self.downloads = []
    }
  }

  // MARK: - Save

  /// Persists a download entry to SQLite. If an entry with the same `id` already exists,
  /// it is updated in-place via `save(db)`.
  ///
  /// **State Consistency Architecture**:
  /// Database persistence is the single source of truth. Mutations are reflected in `self.downloads`
  /// **only** after `databaseManager.writer.write` succeeds.
  func save(_ download: OfflineChartDownload) async throws {
    let record = GeoGarageDownloadRecord(domainModel: download)
    do {
      try await databaseManager.writer.write { db in
        try record.save(db)
      }
      var snapshot = downloads
      if let existingIndex = snapshot.firstIndex(where: { $0.id == download.id }) {
        snapshot[existingIndex] = download
      } else {
        snapshot.insert(download, at: 0)
      }
      self.downloads = snapshot
      Logger.caas.debug("Saved download \(download.id.uuidString, privacy: .public) to database.")
    } catch {
      Logger.caas.error("Failed to persist download \(download.id.uuidString, privacy: .public) to database: \(error, privacy: .public)")
      throw error
    }
  }

  // MARK: - Delete

  /// Deletes a download record matching `id` from SQLite and updates memory state.
  /// Note: Does not delete the actual `.mbtiles` file on disk.
  func delete(id: UUID) async throws {
    do {
      _ = try await databaseManager.writer.write { db in
        try GeoGarageDownloadRecord.deleteOne(db, key: id.uuidString)
      }
      self.downloads.removeAll { $0.id == id }
      Logger.caas.debug("Deleted download \(id.uuidString, privacy: .public) from database.")
    } catch {
      Logger.caas.error("Failed to delete download \(id.uuidString, privacy: .public) from database: \(error, privacy: .public)")
      throw error
    }
  }

  // MARK: - Query

  /// Returns the timestamp of the latest successful download for the specified `layerID` from the in-memory cache.
  /// Used for fast synchronous queries in the UI.
  func lastDownloadDate(for layerID: String) -> Date? {
    downloads
      .filter { $0.layerID == layerID }
      .max(by: { $0.downloadDate < $1.downloadDate })
      .map { $0.downloadDate }
  }

  /// Returns the timestamp of the latest download for `layerID` in O(1) directly from SQLite via index aggregation.
  func fetchLastDownloadDate(for layerID: String) async throws -> Date? {
    try await databaseManager.reader.read { db in
      let maxTimestamp = try Double.fetchOne(
        db,
        GeoGarageDownloadRecord
          .filter(GeoGarageDownloadRecord.Columns.layer_id == layerID)
          .select(max(GeoGarageDownloadRecord.Columns.download_timestamp_unix))
      )
      return maxTimestamp.map { Date(timeIntervalSince1970: $0) }
    }
  }
}
