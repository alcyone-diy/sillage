//
//  GeoGarageLayerRepository.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog
import GRDB

@MainActor
protocol GeoGarageLayerRepositoryProtocol: AnyObject, Sendable {
  var layers: [GeoGarageLayer] { get }
  func loadCachedLayers() async -> [GeoGarageLayer]
  func saveLayers(_ layers: [GeoGarageLayer]) async
  func clearCache() async
}

@Observable
@MainActor
final class GeoGarageLayerRepository: GeoGarageLayerRepositoryProtocol {
  private(set) var layers: [GeoGarageLayer] = []
  private let databaseManager: DatabaseManager
  private let legacyCacheFileURL: URL?

  init(databaseManager: DatabaseManager, legacyCacheFileURL: URL? = nil) {
    self.databaseManager = databaseManager
    if let legacyCacheFileURL {
      self.legacyCacheFileURL = legacyCacheFileURL
    } else if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
      self.legacyCacheFileURL = cachesDir.appendingPathComponent("geogarage_layers.json")
    } else {
      self.legacyCacheFileURL = nil
    }
  }

  func loadCachedLayers() async -> [GeoGarageLayer] {
    await migrateAndRemoveLegacyCacheFileIfNeeded()

    do {
      let loadedLayers = try await databaseManager.reader.read { db in
        try fetchSortedLayers(db)
      }
      self.layers = loadedLayers
      Logger.storage.info("Loaded \(loadedLayers.count, privacy: .public) GeoGarage layer(s) from database.")
      return loadedLayers
    } catch {
      Logger.storage.error("Failed to load cached GeoGarage layers from database: \(error, privacy: .public)")
      self.layers = []
      return []
    }
  }

  func saveLayers(_ newLayers: [GeoGarageLayer]) async {
    do {
      let sortedLayers = try await databaseManager.writer.write { db in
        try GeoGarageLayerRecord.deleteAll(db)
        for layer in newLayers {
          let record = GeoGarageLayerRecord(domainModel: layer)
          try record.save(db)
        }
        return try fetchSortedLayers(db)
      }
      self.layers = sortedLayers
      Logger.storage.debug("Successfully saved \(sortedLayers.count, privacy: .public) GeoGarage layers to database.")
      await removeLegacyCacheFile()
    } catch {
      Logger.storage.error("Failed to save GeoGarage layers to database: \(error, privacy: .public)")
    }
  }

  func clearCache() async {
    do {
      _ = try await databaseManager.writer.write { db in
        try GeoGarageLayerRecord.deleteAll(db)
      }
      self.layers = []
      Logger.storage.debug("GeoGarage layer cache cleared from database.")
      await removeLegacyCacheFile()
    } catch {
      Logger.storage.error("Failed to clear GeoGarage layer cache from database: \(error, privacy: .public)")
    }
  }

  // MARK: - Query Helper

  private nonisolated func fetchSortedLayers(_ db: Database) throws -> [GeoGarageLayer] {
    try GeoGarageLayerRecord
      .order(GeoGarageLayerRecord.Columns.brandName.asc, GeoGarageLayerRecord.Columns.layer.asc)
      .fetchAll(db)
      .map(\.domainModel)
  }

  // MARK: - Legacy Cache Cleanup

  private enum LegacyCacheLoadResult: Sendable {
    case notFound
    case loaded([GeoGarageLayer])
    case corrupted
    case readFailed
  }

  private func migrateAndRemoveLegacyCacheFileIfNeeded() async {
    guard let legacyURL = legacyCacheFileURL else { return }

    // Déporte toute lecture synchrone disque hors du MainActor
    let loadResult: LegacyCacheLoadResult = await Task.detached(priority: .background) {
      guard FileManager.default.fileExists(atPath: legacyURL.path) else { return .notFound }
      let data: Data
      do {
        data = try Data(contentsOf: legacyURL)
      } catch {
        Logger.storage.error("Failed to read legacy GeoGarage layer cache file: \(error, privacy: .public)")
        return .readFailed
      }
      do {
        let layers = try JSONDecoder().decode([GeoGarageLayer].self, from: data)
        return .loaded(layers)
      } catch {
        Logger.storage.error("Failed to decode corrupted legacy GeoGarage layer cache file: \(error, privacy: .public)")
        return .corrupted
      }
    }.value

    switch loadResult {
    case .notFound, .readFailed:
      return
    case .corrupted:
      await removeLegacyCacheFile()
    case .loaded(let legacyLayers):
      if legacyLayers.isEmpty {
        await removeLegacyCacheFile()
        return
      }
      do {
        try await databaseManager.writer.write { db in
          let existingCount = try GeoGarageLayerRecord.fetchCount(db)
          if existingCount == 0 {
            for layer in legacyLayers {
              let record = GeoGarageLayerRecord(domainModel: layer)
              try record.save(db)
            }
          }
        }
        await removeLegacyCacheFile()
      } catch {
        Logger.storage.error("Failed to migrate legacy GeoGarage layers to database: \(error, privacy: .public)")
      }
    }
  }

  private func removeLegacyCacheFile() async {
    guard let legacyURL = legacyCacheFileURL else { return }

    // Déporte toute suppression synchrone disque hors du MainActor
    await Task.detached(priority: .background) {
      guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
      do {
        try FileManager.default.removeItem(at: legacyURL)
        Logger.storage.debug("Removed legacy GeoGarage layer cache file: \(legacyURL.path, privacy: .public)")
      } catch {
        Logger.storage.error("Failed to remove legacy GeoGarage layer cache file: \(error, privacy: .public)")
      }
    }.value
  }
}
