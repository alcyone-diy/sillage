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

@MainActor
protocol GeoGarageLayerRepositoryProtocol: AnyObject {
  var layers: [GeoGarageLayer] { get }
  func loadCachedLayers() async -> [GeoGarageLayer]
  func saveLayers(_ layers: [GeoGarageLayer]) async
  func clearCache() async
}

@Observable
@MainActor
final class GeoGarageLayerRepository: GeoGarageLayerRepositoryProtocol {
  private(set) var layers: [GeoGarageLayer] = []
  private let cacheFileURL: URL

  init(cacheFileURL: URL? = nil) {
    if let cacheFileURL {
      self.cacheFileURL = cacheFileURL
    } else if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
      self.cacheFileURL = cachesDir.appendingPathComponent("geogarage_layers.json")
    } else {
      let tempDir = FileManager.default.temporaryDirectory
      self.cacheFileURL = tempDir.appendingPathComponent("geogarage_layers.json")
    }
  }

  func loadCachedLayers() async -> [GeoGarageLayer] {
    let url = cacheFileURL
    let loadedLayers = await Task.detached(priority: .userInitiated) { () -> [GeoGarageLayer] in
      guard FileManager.default.fileExists(atPath: url.path) else { return [] }
      do {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([GeoGarageLayer].self, from: data)
        return decoded
      } catch {
        Logger.storage.error("Failed to load cached GeoGarage layers: \(error, privacy: .public)")
        return []
      }
    }.value

    self.layers = loadedLayers
    return loadedLayers
  }

  func saveLayers(_ newLayers: [GeoGarageLayer]) async {
    self.layers = newLayers
    let url = cacheFileURL
    await Task.detached(priority: .background) {
      do {
        let data = try JSONEncoder().encode(newLayers)
        try data.write(to: url, options: .atomic)
        Logger.storage.debug("Successfully saved \(newLayers.count, privacy: .public) GeoGarage layers to cache.")
      } catch {
        Logger.storage.error("Failed to save GeoGarage layers to cache: \(error, privacy: .public)")
      }
    }.value
  }

  func clearCache() async {
    self.layers = []
    let url = cacheFileURL
    await Task.detached(priority: .background) {
      if FileManager.default.fileExists(atPath: url.path) {
        do {
          try FileManager.default.removeItem(at: url)
          Logger.storage.debug("GeoGarage layer cache cleared.")
        } catch {
          Logger.storage.error("Failed to clear GeoGarage layer cache: \(error, privacy: .public)")
        }
      }
    }.value
  }
}
