//
//  MeasureToolViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import Observation
import OSLog

/// Represents the strict state machine for the 2-point map measurement tool.
/// Guarantees compile-time safety: either completely inactive, or active with two non-optional valid coordinates.
public enum MeasureState: Equatable, Sendable {
  case inactive
  case active(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)
}

/// Denotes which measurement pin is currently selected for map-tap repositioning.
public enum ActiveMeasurePin: Sendable, Equatable {
  case start
  case end
}

/// State manager for the 2-point nautical measurement tool.
/// Manages geographic state (CLLocationCoordinate2D, Measurement) and interaction flags.
@Observable
@MainActor
final class MeasureToolViewModel {

  // MARK: - State

  private(set) var state: MeasureState = .inactive
  var activePin: ActiveMeasurePin = .end
  var isDraggingPin: Bool = false

  // MARK: - Computed Properties

  var isActive: Bool {
    state != .inactive
  }

  var startCoordinate: CLLocationCoordinate2D? {
    if case .active(let start, _) = state {
      return start
    }
    return nil
  }

  var endCoordinate: CLLocationCoordinate2D? {
    if case .active(_, let end) = state {
      return end
    }
    return nil
  }

  /// Physical distance between start and end points as a strict Foundation `Measurement<UnitLength>`.
  var distance: Measurement<UnitLength>? {
    guard case .active(let start, let end) = state else { return nil }
    return start.distance(to: end)
  }

  /// Initial great circle compass bearing from start to end coordinate.
  /// Technical Design Choice: Identical coordinates return `nil` as bearing to self is indeterminate.
  var bearing: Measurement<UnitAngle>? {
    guard case .active(let start, let end) = state else { return nil }
    return start.greatCircleBearing(to: end)
  }

  /// Reciprocal (back) great circle compass bearing from end to start coordinate.
  /// Returns `nil` when inactive or when coordinates are identical.
  var reciprocalBearing: Measurement<UnitAngle>? {
    guard case .active(let start, let end) = state else { return nil }
    return end.greatCircleBearing(to: start)
  }

  // MARK: - Actions

  /// Activates the measurement tool with explicit initial start and end geographic positions.
  func start(at start: CLLocationCoordinate2D, initialEnd: CLLocationCoordinate2D) {
    Logger.navigation.info("Starting measure tool from (\(start.latitude, privacy: .public), \(start.longitude, privacy: .public)) to (\(initialEnd.latitude, privacy: .public), \(initialEnd.longitude, privacy: .public))")
    self.state = .active(start: start, end: initialEnd)
    self.activePin = .end
  }

  /// Updates the geographic location of the start marker (Pin A).
  func updateStart(to coordinate: CLLocationCoordinate2D) {
    guard case .active(_, let currentEnd) = state else { return }
    self.state = .active(start: coordinate, end: currentEnd)
  }

  /// Updates the geographic location of the end marker (Pin B).
  func updateEnd(to coordinate: CLLocationCoordinate2D) {
    guard case .active(let currentStart, _) = state else { return }
    self.state = .active(start: currentStart, end: coordinate)
  }

  /// Handles a map tap event.
  /// Neither Pin A nor Pin B moves on a simple tap, preventing accidental repositioning.
  /// The currently selected pin only moves via an explicit long press or direct drag gesture.
  func handleMapTap(at coordinate: CLLocationCoordinate2D) {
    // Technical Design Choice: Both Pin A and Pin B are protected against accidental single-tap movement.
  }

  /// Handles a map long-press event when the measurement tool is active.
  /// Relocates whichever pin is currently active (Pin A or Pin B).
  func handleMapLongPress(at coordinate: CLLocationCoordinate2D) {
    guard isActive else { return }
    switch activePin {
    case .start:
      updateStart(to: coordinate)
    case .end:
      updateEnd(to: coordinate)
    }
  }

  /// Deactivates the measurement tool and resets state to `.inactive`.
  func stop() {
    Logger.navigation.info("Stopping measure tool")
    self.state = .inactive
    self.activePin = .end
    self.isDraggingPin = false
  }
}
