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

/// A ViewModel responsible for managing the state of the offline map region selection process.
/// It coordinates the crop box dimensions, calculates estimated download areas, and handles interactions with the `OfflineMapManager`.
@Observable
@MainActor
final class OfflineSelectionViewModel {
  let offlineMapManager: OfflineMapManager
  let offlineMapDownloadService: OfflineMapDownloadService
  
  /// The geographically accurate bounding box derived from the UI crop box.
  @ObservationIgnored private(set) var selectedBounds: GeographicBoundingBox?
  
  /// Indicates whether the user is currently actively selecting an offline region.
  var isSelectionModeActive: Bool = false
  
  /// The estimated surface area of the currently selected bounds, used to warn the user about download limits.
  var estimatedArea: Measurement<UnitArea>?
  
  /// Indicates whether the currently selected area fits within the maximum allowed download limits.
  var isValidSize: Bool = false
  
  /// The default width ratio relative to the smallest map dimension.
  let cropBoxWidthRatio = 0.7
  
  /// The default aspect ratio (height/width) of the selection crop box.
  let cropBoxAspect = 0.75
  
  /// The user-defined dimension and position of the selection crop box. If nil, defaults are applied based on screen size.
  private(set) var cropRect: CGRect?
  
  private var calculationTask: Task<Void, Never>?
  private let maxArea = AppConstants.Cartography.Offline.maxDownloadArea
  
  init(offlineMapManager: OfflineMapManager, offlineMapDownloadService: OfflineMapDownloadService) {
    self.offlineMapManager = offlineMapManager
    self.offlineMapDownloadService = offlineMapDownloadService
  }
  
  /// Updates the geographical bounding box linked to the UI selection area.
  /// It debounces the area computation to prevent excessive calculation during rapid map panning.
  /// - Parameter bounds: The new computed geographic bounding box.
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
  
  /// Updates the position and size of the selection crop box.
  ///
  /// This method must only be called at the end of the resize gesture (`.onEnded`)
  /// to conserve CPU and battery. Continuous updates during the *drag* phase
  /// would trigger heavy MapLibre geometric and geospatial recalculations.
  /// - Parameter rect: The new final frame of the selection area in screen coordinates.
  func updateCropRect(_ rect: CGRect) {
    self.cropRect = rect
  }
  
  /// Initiates the offline map download using the current geographic bounding box.
  /// - Parameter chartSource: The active chart source to derive the specific style JSON or map layers for download.
  func startDownload(chartSource: ChartSource?) {
    guard let bounds = selectedBounds else { return }
    
    // UI reset MUST be synchronous on the MainActor BEFORE the async download process
    isSelectionModeActive = false
    selectedBounds = nil
    cropRect = nil
    calculationTask?.cancel()
    
    Task {
      do {
        try await offlineMapDownloadService.startDownload(bounds: bounds, chartSource: chartSource)
      } catch {
        Logger.offline.error("Failed to start offline download: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
  
  /// Fully clears the active selection and drops out of selection mode.
  func resetSelection() {
    offlineMapManager.reset()
    isSelectionModeActive = false
    selectedBounds = nil
    cropRect = nil
    calculationTask?.cancel()
  }
  
  /// Cancels any active offline map download process.
  func cancelDownload() {
    offlineMapManager.cancelDownload()
  }
}
