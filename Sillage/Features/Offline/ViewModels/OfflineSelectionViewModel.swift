//
//  OfflineSelectionViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation
import Observation
import OSLog

@Observable
@MainActor
final class OfflineSelectionViewModel {
  let offlineMapManager: OfflineMapManager
  
  @ObservationIgnored private(set) var selectedBounds: GeographicBoundingBox?
  
  var isSelectionModeActive: Bool = false
  var estimatedArea: Measurement<UnitArea>?
  var isValidSize: Bool = false
  
  let cropBoxWidthRatio = 0.7
  let cropBoxAspect = 0.75
  
  private var calculationTask: Task<Void, Never>?
  private let maxArea = AppConstants.Cartography.Offline.maxDownloadArea
  
  init(offlineMapManager: OfflineMapManager) {
    self.offlineMapManager = offlineMapManager
  }
  
  func updateBoundingBox(_ bounds: GeographicBoundingBox) {
    guard isSelectionModeActive else { return }
    self.selectedBounds = bounds
    
    calculationTask?.cancel()
    calculationTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(300))
        guard let self = self else { return }
        
        let area = bounds.estimatedArea
        self.estimatedArea = area
        self.isValidSize = area.converted(to: .squareNauticalMiles).value <= self.maxArea.value
      } catch is CancellationError {
        // Task was cancelled
      } catch {
        // Ignore
      }
    }
  }
  
  func startDownload(chartSource: ChartSource?) {
    guard let bounds = selectedBounds else { return }
    let regionName = "Area - \(Date().formatted(.dateTime.day().month().year().hour().minute()))"
    
    var styleURL = AppConstants.Cartography.defaultStyleURL
    
    if let source = chartSource, case .remoteGeoGarage(let clientID, let layerID) = source {
        if let dynamicStyleURL = generateDynamicStyleJSON(forLayer: layerID, clientID: clientID) {
            styleURL = dynamicStyleURL
        } else {
            Logger.offline.error("Failed to generate dynamic style for layer \(layerID, privacy: .public), falling back to default.")
        }
    }
    
    guard let finalStyleURL = styleURL else {
      Logger.offline.error("Failed to retrieve style URL for offline region.")
      return
    }
    
    offlineMapManager.downloadRegion(bounds: bounds, styleURL: finalStyleURL, regionName: regionName)
  }
  
  private func generateDynamicStyleJSON(forLayer layerID: String, clientID: String) -> URL? {
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
          "tileSize": 256,
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
    guard let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
    let stylesDir = cachesDir.appendingPathComponent("DynamicStyles", isDirectory: true)
    
    do {
      if !fm.fileExists(atPath: stylesDir.path) {
        try fm.createDirectory(at: stylesDir, withIntermediateDirectories: true)
      }
      let fileURL = stylesDir.appendingPathComponent("geogarage-\(layerID).json")
      try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
      return fileURL
    } catch {
      Logger.offline.error("Failed to write dynamic style JSON: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }
  
  func close() {
    offlineMapManager.reset()
    isSelectionModeActive = false
    selectedBounds = nil
  }
  
  func cancelDownload() {
    offlineMapManager.cancelDownload()
  }
}
