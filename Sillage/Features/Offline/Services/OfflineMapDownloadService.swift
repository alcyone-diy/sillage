//
//  OfflineMapDownloadService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog


public enum OfflineMapDownloadError: LocalizedError, Equatable {
  case missingDefaultStyleURL
  
  public var errorDescription: String? {
    switch self {
    case .missingDefaultStyleURL:
      return String(localized: "Default style URL is not available.")
    }
  }
}

/// A service responsible for preparing and orchestrating offline map downloads.
@Observable
@MainActor
final class OfflineMapDownloadService {
  let offlineMapManager: OfflineMapManagerProtocol
  
  init(offlineMapManager: OfflineMapManagerProtocol) {
    self.offlineMapManager = offlineMapManager
  }

  /// Initiates the offline map download using the specified geographic bounding box.
  /// - Parameters:
  ///   - bounds: The geographical area to download.
  ///   - chartSource: The active chart source to derive the specific style JSON or map layers for download.
  func startDownload(bounds: GeographicBoundingBox, chartSource: ChartSource?) async throws {
    let regionName = "Area - \(Date().formatted(.dateTime.day().month().year().hour().minute()))"
    
    let styleURL: URL
    
    if let source = chartSource, case .remoteGeoGarage(let clientID, let layerID) = source {
        styleURL = try await generateDynamicStyleJSON(forLayer: layerID, clientID: clientID)
    } else {
        guard let defaultURL = AppConstants.Cartography.defaultStyleURL else {
            throw OfflineMapDownloadError.missingDefaultStyleURL
        }
        styleURL = defaultURL
    }
    
    offlineMapManager.downloadRegion(bounds: bounds, styleURL: styleURL, regionName: regionName)
  }
  
  /// Generates a dynamic style JSON tailored for the selected remote GeoGarage layer.
  /// - Parameters:
  ///   - layerID: The map layer ID.
  ///   - clientID: The authorization client ID.
  /// - Returns: A file URL pointing to the locally generated JSON style.
  func generateDynamicStyleJSON(forLayer layerID: String, clientID: String) async throws -> URL {
    let jsonString = """
    {
      "version": 8,
      "name": "GeoGarage Raster - \(layerID)",
      "sources": {
        "geogarage-raster": {
          "type": "raster",
          "tiles": [
            "https://tiles.geogarage.com/\(clientID)/\(layerID)/{z}/{x}/{y}.png"
          ],
          "tileSize": \(Int(AppConstants.Cartography.Tile.rasterTileSize)),
          "maxzoom": 16
        }
      },
      "layers": [
        {
          "id": "geogarage-layer",
          "type": "raster",
          "source": "geogarage-raster",
          "minzoom": 0,
          "maxzoom": 18
        }
      ]
    }
    """
    
    let fm = FileManager.default
    guard let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      throw NSError(domain: "OfflineMapDownloadService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Caches directory not found"])
    }
    let stylesDir = cachesDir.appendingPathComponent("DynamicStyles", isDirectory: true)
    
    return try await Task.detached {
      if !fm.fileExists(atPath: stylesDir.path) {
        try fm.createDirectory(at: stylesDir, withIntermediateDirectories: true)
      }
      let fileURL = stylesDir.appendingPathComponent("geogarage-\(layerID).json")
      try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
      return fileURL
    }.value
  }
}
