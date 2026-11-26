//
//  MapFeatureVocabulary.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Standardized keys for the MLNFeature attributes dictionary.
enum MapFeatureKey: String {
  case type = "featureType"
  case id = "id"
  case name = "name"
  case course = "course"
  case isStale = "isStale"
  case isDegraded = "isDegraded"
  case isMajorTick = "isMajorTick"
  case color = "color"
  case status = "status"
  case icon = "icon"
  case sortKey = "sortKey"
}

/// Standardized values for the `MapFeatureKey.type` attribute.
enum MapFeatureType: String {
  case anchorPoint = "anchorPoint"
  case anchorRadius = "anchorRadius"
  case anchorRode = "anchorRode"
  case anchorEvitement = "anchorEvitement"
  case bearingLine = "bearingLine"
  case vectorLine = "vectorLine"
  case vectorTick = "vectorTick"
  case vessel = "vessel"
  case waypoint = "waypoint"
  case measureLine = "measureLine"
  case measurePin = "measurePin"
  case targetAimingCrosshair = "targetAimingCrosshair"
  case offlineMask = "offlineMask"
  case offlineRegionsBorder = "offlineRegionsBorder"
  case offlineHighlight = "offlineHighlight"
  case offlineSelection = "offlineSelection"
  case offlineSelectionCorners = "offlineSelectionCorners"
}

/// Standardized GPU sprite image names registered in `MLNStyle`.
enum MapSpriteIdentifier {
  static let vesselCursor = "vessel-cursor"
  static let targetAimingCrosshair = "target-aiming-crosshair"

  static func anchorIcon(for status: AnchorVisualStatus) -> String {
    "anchor-icon-\(status.rawValue)"
  }

  static func measurePinIcon(for pin: ActiveMeasurePin, isSelected: Bool) -> String {
    let pinLetter = pin == .start ? "a" : "b"
    let stateKey = isSelected ? "selected" : "idle"
    return "measure-pin-\(pinLetter)-\(stateKey)"
  }
}
