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
  @MainActor func delete(ids: [UUID]) async throws
  @MainActor func lastDownloadDate(for layerID: String) -> Date?
  @MainActor func fetchLastDownloadDate(for layerID: String) async throws -> Date?
}

extension GeoGarageDownloadRepositoryProtocol {
  @MainActor
  func delete(ids: [UUID]) async throws {
    for id in ids {
      try await delete(id: id)
    }
  }
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
  private(set) var downloads: [OfflineChartDownload] = [] {
    didSet {
      for continuation in downloadsDidChangeContinuations.values {
        continuation.yield()
      }
    }
  }

  @ObservationIgnored
  nonisolated(unsafe) private var downloadsDidChangeContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

  /// Multicast stream emitting whenever `downloads` changes.
  var downloadsDidChangeStream: AsyncStream<Void> {
    let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    let id = UUID()
    downloadsDidChangeContinuations[id] = continuation
    continuation.onTermination = { @Sendable [weak self] _ in
      Task { @MainActor [weak self] in
        self?.downloadsDidChangeContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }

  private let databaseManager: DatabaseManager

  // MARK: - Init

  init(databaseManager: DatabaseManager) {
    self.databaseManager = databaseManager
  }

  deinit {
    for continuation in downloadsDidChangeContinuations.values {
      continuation.finish()
    }
    downloadsDidChangeContinuations.removeAll()
  }

  // MARK: - Query Helper

  private nonisolated func fetchSortedDownloads(_ db: Database) throws -> [OfflineChartDownload] {
    try GeoGarageDownloadRecord
      .order(
        GeoGarageDownloadRecord.Columns.download_timestamp_unix.desc,
        GeoGarageDownloadRecord.Columns.id.asc
      )
      .fetchAll(db)
      .compactMap { $0.toDomain() }
  }

  // MARK: - Load

  /// Loads downloaded packages from the SQLite database.
  /// Should be called during app bootstrap before accessing `downloads`.
  func load() async {
    do {
      self.downloads = try await databaseManager.reader.read { db in
        try fetchSortedDownloads(db)
      }
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
  /// **only** after `databaseManager.writer.write` succeeds, using the canonical sorted query.
  func save(_ download: OfflineChartDownload) async throws {
    let record = GeoGarageDownloadRecord(domainModel: download)
    do {
      let sortedDownloads = try await databaseManager.writer.write { db in
        try record.save(db)
        return try fetchSortedDownloads(db)
      }
      self.downloads = sortedDownloads
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

  /// Batch deletes download records matching `ids` from SQLite and updates memory state.
  /// Note: Does not delete the actual `.mbtiles` files on disk.
  func delete(ids: [UUID]) async throws {
    guard !ids.isEmpty else { return }
    let idStrings = ids.map(\.uuidString)
    let idsSet = Set(ids)
    do {
      _ = try await databaseManager.writer.write { db in
        try GeoGarageDownloadRecord.deleteAll(db, keys: idStrings)
      }
      self.downloads.removeAll { idsSet.contains($0.id) }
      Logger.caas.debug("Deleted \(idStrings.count, privacy: .public) downloads from database.")
    } catch {
      Logger.caas.error("Failed to delete downloads from database: \(error, privacy: .public)")
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
