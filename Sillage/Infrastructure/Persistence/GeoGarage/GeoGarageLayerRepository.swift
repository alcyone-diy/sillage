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
      let records = try await databaseManager.reader.read { db in
        try GeoGarageLayerRecord
          .order(GeoGarageLayerRecord.Columns.brandName.asc, GeoGarageLayerRecord.Columns.layer.asc)
          .fetchAll(db)
      }
      let loadedLayers = records.map(\.domainModel)
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
      try await databaseManager.writer.write { db in
        try GeoGarageLayerRecord.deleteAll(db)
        for layer in newLayers {
          let record = GeoGarageLayerRecord(domainModel: layer)
          try record.save(db)
        }
      }
      self.layers = newLayers
      Logger.storage.debug("Successfully saved \(newLayers.count, privacy: .public) GeoGarage layers to database.")
    } catch {
      Logger.storage.error("Failed to save GeoGarage layers to database: \(error, privacy: .public)")
    }
    await removeLegacyCacheFile()
  }

  func clearCache() async {
    do {
      _ = try await databaseManager.writer.write { db in
        try GeoGarageLayerRecord.deleteAll(db)
      }
      self.layers = []
      Logger.storage.debug("GeoGarage layer cache cleared from database.")
    } catch {
      Logger.storage.error("Failed to clear GeoGarage layer cache from database: \(error, privacy: .public)")
    }
    await removeLegacyCacheFile()
  }

  // MARK: - Legacy Cache Cleanup

  private func migrateAndRemoveLegacyCacheFileIfNeeded() async {
    guard let legacyURL = legacyCacheFileURL else { return }

    // Déporte toute lecture synchrone disque hors du MainActor
    let legacyLayers: [GeoGarageLayer]? = await Task.detached(priority: .background) {
      guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
      do {
        let data = try Data(contentsOf: legacyURL)
        return try JSONDecoder().decode([GeoGarageLayer].self, from: data)
      } catch {
        Logger.storage.error("Failed to decode legacy GeoGarage layer cache file: \(error, privacy: .public)")
        return nil
      }
    }.value

    if let legacyLayers, !legacyLayers.isEmpty {
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
      } catch {
        Logger.storage.error("Failed to migrate legacy GeoGarage layers to database: \(error, privacy: .public)")
      }
    }

    await removeLegacyCacheFile()
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
