//
//  MapLibreFeatureFactory.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import MapLibre

struct AnchorFeatures {
  let pointFeature: MLNPointFeature?
  let radiusFeature: MLNPolygonFeature?
}

@MainActor
enum MapLibreFeatureFactory {
  static func createAnchorFeatures(from state: AnchorVisualState?) -> AnchorFeatures {
    guard let state else {
      return AnchorFeatures(pointFeature: nil, radiusFeature: nil)
    }
    
    let pointFeature = MLNPointFeature()
    pointFeature.coordinate = state.pointCoordinate
    pointFeature.attributes = [
      MapFeatureKey.type.rawValue: MapFeatureType.anchorPoint.rawValue,
    ]
    
    let radiusFeature: MLNPolygonFeature? = {
      guard let radius = state.radius,
            let polygonCoords = state.pointCoordinate.circularPolygon(radius: radius) else {
        return nil
      }
      var coords = polygonCoords
      let feature = MLNPolygonFeature(coordinates: &coords, count: UInt(coords.count))
      feature.attributes = [
        MapFeatureKey.type.rawValue: MapFeatureType.anchorRadius.rawValue,
      ]
      return feature
    }()
    
    return AnchorFeatures(pointFeature: pointFeature, radiusFeature: radiusFeature)
  }
}
