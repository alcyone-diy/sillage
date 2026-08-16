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

// MARK: - Protocol

@MainActor
protocol GeoGarageDownloadRepositoryProtocol: AnyObject {
  var downloads: [OfflineChartDownload] { get }
  func load() async
  func save(_ download: OfflineChartDownload) async
  func delete(id: UUID) async
  func lastDownloadDate(for layerID: String) -> Date?
}

// MARK: - Implementation

/// `@MainActor` repository managing the collection of locally downloaded CAAS MBTiles packages.
///
/// **Concurrency Architecture**:
/// - The observable state (`downloads`) is isolated on `@MainActor` for reactive UI bindings.
/// - All disk read/write operations are delegated to `LocalFilePersistenceActor`,
///   a dedicated Swift 6 actor that serializes JSON file access to prevent race conditions.
@Observable
@MainActor
final class GeoGarageDownloadRepository: GeoGarageDownloadRepositoryProtocol {
  private(set) var downloads: [OfflineChartDownload] = []

  private let persistence: LocalFilePersistenceActor
  private let fileURL: URL

  // MARK: - Init

  init(persistence: LocalFilePersistenceActor, fileURL: URL? = nil) {
    self.persistence = persistence

    if let fileURL {
      self.fileURL = fileURL
    } else if let documentsDir = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first {
      self.fileURL = documentsDir.appendingPathComponent("geogarage_downloads.json")
    } else {
      self.fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("geogarage_downloads.json")
      Logger.caas.error("Documents directory unavailable, falling back to temp directory.")
    }
  }

  // MARK: - Load

  /// Loads downloaded packages list from disk.
  /// Should be called during app bootstrap before accessing `downloads`.
  func load() async {
    do {
      let loaded: [OfflineChartDownload]? = try await persistence.load(from: fileURL)
      self.downloads = loaded ?? []
      Logger.caas.info("Loaded \(self.downloads.count, privacy: .public) offline chart download(s) from cache.")
    } catch {
      Logger.caas.error("Failed to load download repository: \(error, privacy: .public)")
      self.downloads = []
    }
  }

  // MARK: - Save

  /// Persists a download entry. If an entry with the same `id` already exists,
  /// it is updated in-place (idempotent for retry safety).
  ///
  /// **State Consistency Architecture**:
  /// Disk persistence is the single source of truth. Mutations are performed on a local snapshot
  /// and `self.downloads` is updated **only** after `persistence.save(snapshot)` succeeds without throwing.
  func save(_ download: OfflineChartDownload) async {
    var snapshot = downloads
    if let existingIndex = snapshot.firstIndex(where: { $0.id == download.id }) {
      snapshot[existingIndex] = download
    } else {
      snapshot.append(download)
    }

    do {
      try await persistence.save(snapshot, to: fileURL)
      self.downloads = snapshot
      Logger.caas.debug("Saved \(snapshot.count, privacy: .public) download(s) to repository.")
    } catch {
      Logger.caas.error("Failed to persist download repository to disk: \(error, privacy: .public)")
    }
  }

  // MARK: - Delete

  /// Deletes a download record matching `id`.
  ///
  /// **State Consistency Architecture**:
  /// `self.downloads` is updated only after the modified snapshot is successfully persisted to disk.
  /// Note: Does not delete the actual `.mbtiles` file on disk.
  func delete(id: UUID) async {
    var snapshot = downloads
    snapshot.removeAll { $0.id == id }

    do {
      try await persistence.save(snapshot, to: fileURL)
      self.downloads = snapshot
      Logger.caas.debug("Deleted download \(id.uuidString, privacy: .public) from repository.")
    } catch {
      Logger.caas.error("Failed to persist repository after deletion: \(error, privacy: .public)")
    }
  }

  // MARK: - Query

  /// Returns the timestamp of the latest successful download for the specified `layerID`.
  /// Used to compare against `GeoGarageLayer.versionDate` to detect available updates.
  func lastDownloadDate(for layerID: String) -> Date? {
    downloads
      .filter { $0.layerID == layerID }
      .max(by: { $0.downloadDate < $1.downloadDate })
      .map { $0.downloadDate }
  }
}
