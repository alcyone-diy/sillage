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

/// Represents a single offline chart region label to be displayed at the centroid of a saved chart.
public struct OfflineRegionLabelInfo: Sendable, Equatable {
  public let id: String
  public let name: String
  public let coordinate: CLLocationCoordinate2D

  public nonisolated init(id: String, name: String, coordinate: CLLocationCoordinate2D) {
    self.id = id
    self.name = name
    self.coordinate = coordinate
  }
}

/// Represents a projected screen label for an offline region with its 2D screen coordinate and visibility.
public struct OfflineRegionScreenLabel: Identifiable, Sendable, Equatable {
  public let id: String
  public let name: String
  public let screenPoint: CGPoint
  public let isVisible: Bool

  public nonisolated init(id: String, name: String, screenPoint: CGPoint, isVisible: Bool) {
    self.id = id
    self.name = name
    self.screenPoint = screenPoint
    self.isVisible = isVisible
  }
}

/// Represents the visual state of the offline mask rendered directly on MapLibre.
///
/// ### Architecture & Performance Design:
/// - `maskHoles` contains topologically merged, non-intersecting closed coordinate rings
///   for both saved offline regions and the active selection area, ensuring the selection area is NEVER dimmed.
/// - `savedOfflinePolygons` contains non-overlapping closed rings of saved offline packages only,
///   used to render clean dashed boundary outlines around existing saved charts.
/// - `regionLabels` contains validated, non-empty display names and geographic centroids
///   for each saved offline region matching the active chart layer.
public struct OfflineMaskVisualState: Sendable, Equatable {
  /// Indicates whether the offline mask layer should be actively rendered.
  public let isActive: Bool

  /// The pre-computed, non-overlapping closed polygon rings representing holes in the mask (saved offline regions + active selection area).
  public let maskHoles: [[CLLocationCoordinate2D]]

  /// The pre-computed, non-overlapping closed polygon rings representing saved offline regions only (used for border outlines).
  public let savedOfflinePolygons: [[CLLocationCoordinate2D]]

  /// The pre-computed geographic center coordinates and non-empty display names for saved offline region labels.
  public let regionLabels: [OfflineRegionLabelInfo]

  public nonisolated init(
    isActive: Bool,
    maskHoles: [[CLLocationCoordinate2D]] = [],
    savedOfflinePolygons: [[CLLocationCoordinate2D]] = [],
    regionLabels: [OfflineRegionLabelInfo] = []
  ) {
    self.isActive = isActive
    self.maskHoles = maskHoles
    self.savedOfflinePolygons = savedOfflinePolygons
    self.regionLabels = regionLabels
  }
}
