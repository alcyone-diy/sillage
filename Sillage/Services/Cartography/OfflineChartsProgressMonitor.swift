//
//  OfflineChartsProgressMonitor.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation

/// Aggregates offline chart download progress across MapLibre and GeoGarage engines
/// into a single normalized progress value (`0.0...1.0`) for UI observation.
///
/// Raw engine values are always stored before computing the composite average, and the
/// delta threshold is compared against the last published `progress` so consecutive small
/// increments still accumulate and trigger updates once they cross `minPublishDelta`.
@Observable
@MainActor
final class OfflineChartsProgressMonitor {
  /// Normalized download progress (`0.0...1.0`) when at least one engine is active, or `nil` when idle.
  private(set) var progress: Double? = nil

  /// Indicates whether an offline chart download is currently active on either engine.
  var isDownloading: Bool {
    progress != nil
  }

  @ObservationIgnored
  private var mapLibreProgress: Double?

  @ObservationIgnored
  private var geoGarageProgress: Double?

  @ObservationIgnored
  private var geoGarageObservationTask: Task<Void, Never>?

  @ObservationIgnored
  private let minPublishDelta: Double

  init(minPublishDelta: Double = 0.01) {
    self.minPublishDelta = minPublishDelta
  }

  /// Starts observing a GeoGarage progress stream, resetting any previous observation first.
  func start(geoGarageProgressStream: AsyncStream<Double?>) {
    stop()
    geoGarageObservationTask = Task { @MainActor [weak self] in
      for await value in geoGarageProgressStream {
        guard !Task.isCancelled, let self else { break }
        self.geoGarageProgress = value
        self.updateCompositeProgress()
      }
      // Clear stale GeoGarage progress on natural stream termination without letting
      // a cancelled task overwrite state from a subsequent `start(...)`.
      guard !Task.isCancelled, let self else { return }
      self.geoGarageProgress = nil
      self.updateCompositeProgress()
    }
  }

  /// Stops observing the GeoGarage progress stream and clears its progress state.
  func stop() {
    geoGarageObservationTask?.cancel()
    geoGarageObservationTask = nil
    geoGarageProgress = nil
    updateCompositeProgress()
  }

  /// Updates the raw MapLibre download progress synchronously.
  func updateMapLibreProgress(_ value: Double?) {
    mapLibreProgress = value
    updateCompositeProgress()
  }

  private func updateCompositeProgress() {
    let candidate: Double? = switch (geoGarageProgress, mapLibreProgress) {
    case let (gg?, ml?):
      (gg + ml) / 2.0
    case let (gg?, nil):
      gg
    case let (nil, ml?):
      ml
    case (nil, nil):
      nil
    }

    guard let next = candidate else {
      if progress != nil {
        progress = nil
      }
      return
    }

    guard let current = progress else {
      // Always publish immediately when transitioning from idle (`nil`) to active.
      progress = next
      return
    }

    // Boundary values (`0.0` and `1.0`) bypass the delta filter so start/completion
    // states are never swallowed by throttling.
    if next == 0.0 || next == 1.0 {
      if current != next {
        progress = next
      }
      return
    }

    if abs(next - current) >= minPublishDelta {
      progress = next
    }
  }
}
