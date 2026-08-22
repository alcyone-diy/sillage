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

/// Standardized keys for the MLNFeatures attributes dictionary.
enum MapFeatureKey: String {
  case type = "featureType"
  case id = "id"
  case name = "name"
  case course = "course"
  case isStale = "isStale"
  case isDegraded = "isDegraded"
  case isMajorTick = "isMajorTick"
  case color = "color"
}

/// Standardized values for the MapFeatureKey.type key.
enum MapFeatureType: String {
  case anchorPoint = "anchorPoint"
  case anchorRadius = "anchorRadius"
  case anchorRode = "anchorRode"
  case bearingLine = "bearingLine"
  case vectorLine = "vectorLine"
  case vectorTick = "vectorTick"
  case vessel = "vessel"
  case waypoint = "waypoint"
  case offlineMask = "offlineMask"
  case offlineRegionsBorder = "offlineRegionsBorder"
}
