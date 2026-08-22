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
/// - `maskHoles` contains topologically merged, non-intersecting closed coordinate rings
///   for both saved offline regions and the active selection area, ensuring the selection area is NEVER dimmed.
/// - `savedOfflinePolygons` contains non-overlapping closed rings of saved offline packages only,
///   used to render clean dashed boundary outlines around existing saved charts.
public struct OfflineMaskVisualState: Sendable, Equatable {
  /// Indicates whether the offline mask layer should be actively rendered.
  public let isActive: Bool

  /// The pre-computed, non-overlapping closed polygon rings representing holes in the mask (saved offline regions + active selection area).
  public let maskHoles: [[CLLocationCoordinate2D]]

  /// The pre-computed, non-overlapping closed polygon rings representing saved offline regions only (used for border outlines).
  public let savedOfflinePolygons: [[CLLocationCoordinate2D]]

  public nonisolated init(
    isActive: Bool,
    maskHoles: [[CLLocationCoordinate2D]] = [],
    savedOfflinePolygons: [[CLLocationCoordinate2D]] = []
  ) {
    self.isActive = isActive
    self.maskHoles = maskHoles
    self.savedOfflinePolygons = savedOfflinePolygons
  }
}
