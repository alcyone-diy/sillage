//
//  OfflineMaskVisualState.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Represents the visual state of the offline mask rendered directly on MapLibre.
///
/// ### Architecture & Performance Design:
/// - The active selection crop box is deliberately NOT part of this state to avoid re-tessellating
///   a world-scale polygon in Metal at 60–120 FPS during interactive user gestures (handled by SwiftUI HUD instead).
/// - `offlinePolygons` contains topologically merged, non-intersecting closed coordinate rings
///   computed in a background task via `GeographicBoundingBox.mergeIntoNonIntersectingPolygons(_:)`.
public struct OfflineMaskVisualState: Sendable, Equatable {
  /// Indicates whether the offline mask layer should be actively rendered.
  public let isActive: Bool

  /// The pre-computed, non-overlapping closed polygon rings representing saved offline regions for the active chart layer.
  public let offlinePolygons: [[CLLocationCoordinate2D]]

  public nonisolated init(isActive: Bool, offlinePolygons: [[CLLocationCoordinate2D]] = []) {
    self.isActive = isActive
    self.offlinePolygons = offlinePolygons
  }
}
