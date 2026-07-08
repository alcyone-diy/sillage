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

@Observable
@MainActor
final class OfflineSelectionViewModel {
  
  var isSelectionModeActive: Bool = false
  var estimatedArea: Measurement<UnitArea>?
  var isValidSize: Bool = false
  
  let cropBoxWidthRatio = 0.7
  let cropBoxAspect = 0.75
  
  private var calculationTask: Task<Void, Never>?
  private let maxArea = Measurement(value: 900, unit: UnitArea.squareNauticalMiles)
  
  func updateBoundingBox(_ bounds: GeographicBoundingBox) {
    guard isSelectionModeActive else { return }
    
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
}
