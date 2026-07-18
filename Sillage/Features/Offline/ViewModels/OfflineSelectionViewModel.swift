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
  
  func startDownload() {
    guard let bounds = selectedBounds else { return }
    guard let styleURL = AppConstants.Cartography.defaultStyleURL else {
      Logger.offline.error("Failed to retrieve default style URL from AppConstants")
      return
    }
    let regionName = "Area - \(Date().formatted(.dateTime.day().month().year().hour().minute()))"
    
    offlineMapManager.downloadRegion(bounds: bounds, styleURL: styleURL, regionName: regionName)
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
