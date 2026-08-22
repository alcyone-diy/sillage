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
  let rodeLineFeature: MLNPolylineFeature?
  let evitementLineFeature: MLNPolylineFeature?
}

@MainActor
enum MapLibreFeatureFactory {
  static func createAnchorFeatures(from state: AnchorVisualState?) -> AnchorFeatures {
    guard let state else {
      return AnchorFeatures(pointFeature: nil, radiusFeature: nil, rodeLineFeature: nil, evitementLineFeature: nil)
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
    
    let rodeLineFeature: MLNPolylineFeature? = nil


    let evitementLineFeature: MLNPolylineFeature? = {
      guard state.evitementCoordinates.count >= 2 else {
        return nil
      }
      var coords = state.evitementCoordinates
      let feature = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
      feature.attributes = [
        MapFeatureKey.type.rawValue: "anchor-evitement-line",
      ]
      return feature
    }()
    
    return AnchorFeatures(
      pointFeature: pointFeature,
      radiusFeature: radiusFeature,
      rodeLineFeature: rodeLineFeature,
      evitementLineFeature: evitementLineFeature
    )
  }

  
  static func createVesselFeature(from state: VesselVisualState?) -> MLNPointFeature? {
    guard let state = state else { return nil }
    let feature = MLNPointFeature()
    feature.coordinate = state.coordinate
    var attributes: [String: Any] = [
      MapFeatureKey.type.rawValue: MapFeatureType.vessel.rawValue,
      MapFeatureKey.isStale.rawValue: state.isStale,
      MapFeatureKey.isDegraded.rawValue: state.isDegraded
    ]
    if let course = state.course {
      attributes[MapFeatureKey.course.rawValue] = course.converted(to: .degrees).value
    }
    feature.attributes = attributes
    return feature
  }

  static func createHeadingVectorFeature(from data: HeadingVectorData?) -> MLNShapeCollectionFeature? {
    guard let data = data else { return nil }
    var shapes: [MLNShape] = []
    
    var lineCoords = data.lineCoordinates
    let lineFeature = MLNPolylineFeature(coordinates: &lineCoords, count: UInt(lineCoords.count))
    lineFeature.attributes = [MapFeatureKey.type.rawValue: MapFeatureType.vectorLine.rawValue]
    shapes.append(lineFeature)
    
    for tick in data.majorTickCoordinates {
      let tickFeature = MLNPointFeature()
      tickFeature.coordinate = tick
      tickFeature.attributes = [
        MapFeatureKey.type.rawValue: MapFeatureType.vectorTick.rawValue,
        MapFeatureKey.isMajorTick.rawValue: true,
      ]
      shapes.append(tickFeature)
    }
    
    for tick in data.minorTickCoordinates {
      let tickFeature = MLNPointFeature()
      tickFeature.coordinate = tick
      tickFeature.attributes = [
        MapFeatureKey.type.rawValue: MapFeatureType.vectorTick.rawValue,
        MapFeatureKey.isMajorTick.rawValue: false,
      ]
      shapes.append(tickFeature)
    }
    
    return MLNShapeCollectionFeature(shapes: shapes)
  }

  static func createAccuracyFeature(from state: GpsAccuracyVisualState?) -> MLNPolygonFeature? {
    guard let state = state, !state.coordinates.isEmpty else { return nil }
    var coords = state.coordinates
    let feature = MLNPolygonFeature(coordinates: &coords, count: UInt(coords.count))
    return feature
  }

  static func createSavedTrackFeature(from state: SavedTrackVisualState?) -> MLNShape? {
    guard let state = state, !state.segments.isEmpty else { return nil }
    if state.segments.count == 1 {
      var coordinates = state.segments[0]
      return MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
    } else {
      let polylines = state.segments.map { coords -> MLNPolyline in
        var mutableCoords = coords
        return MLNPolyline(coordinates: &mutableCoords, count: UInt(mutableCoords.count))
      }
      return MLNMultiPolylineFeature(polylines: polylines)
    }
  }

  static func createGoToWaypointFeature(from state: WaypointVisualState?, targetWaypointID: String? = nil) -> MLNPointFeature? {
    guard let state = state else { return nil }
    let feature = MLNPointFeature()
    feature.coordinate = state.coordinate
    let isTarget = (targetWaypointID != nil && state.id == targetWaypointID)
    feature.attributes = [
      MapFeatureKey.type.rawValue: MapFeatureType.waypoint.rawValue,
      MapFeatureKey.id.rawValue: state.id,
      MapFeatureKey.name.rawValue: state.name,
      MapFeatureKey.color.rawValue: state.colorHex,
      "isCalloutTarget": isTarget
    ]
    return feature
  }

  static func createVisibleWaypointsFeature(from states: [WaypointVisualState], targetWaypointID: String? = nil) -> MLNShapeCollectionFeature? {
    guard !states.isEmpty else { return nil }
    let features: [MLNPointFeature] = states.map { waypoint in
      let feature = MLNPointFeature()
      feature.coordinate = waypoint.coordinate
      let isTarget = (targetWaypointID != nil && waypoint.id == targetWaypointID)
      feature.attributes = [
        MapFeatureKey.type.rawValue: MapFeatureType.waypoint.rawValue,
        MapFeatureKey.id.rawValue: waypoint.id,
        MapFeatureKey.name.rawValue: waypoint.name,
        MapFeatureKey.color.rawValue: waypoint.colorHex,
        "isCalloutTarget": isTarget
      ]
      return feature
    }
    return MLNShapeCollectionFeature(shapes: features)
  }

  static func createBearingLineFeature(from state: BearingLineVisualState?) -> MLNPolylineFeature? {
    guard let state = state, state.coordinates.count >= 2 else { return nil }
    var coordinates = state.coordinates
    let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
    var attributes: [String: Any] = [
      MapFeatureKey.type.rawValue: MapFeatureType.bearingLine.rawValue
    ]
    if let color = state.colorHex {
      attributes[MapFeatureKey.color.rawValue] = color
    }
    feature.attributes = attributes
    return feature
  }


  static func createActiveTrackFeature(from points: ArraySlice<TrackPoint>) -> MLNShape? {

    guard points.count >= 2 else { return nil }
    
    var segments: [[CLLocationCoordinate2D]] = []
    var currentSegment: [CLLocationCoordinate2D] = []
    currentSegment.reserveCapacity(points.count)
    var currentSegmentIndex: Int?
    
    for point in points {
      if let currentIdx = currentSegmentIndex, currentIdx != point.segmentIndex {
        if currentSegment.count >= 2 {
          segments.append(currentSegment)
        }
        currentSegment = []
        currentSegment.reserveCapacity(points.count)
      }
      currentSegmentIndex = point.segmentIndex
      currentSegment.append(point.coordinate)
    }
    
    if currentSegment.count >= 2 {
      segments.append(currentSegment)
    }
    
    if segments.count == 1 {
      var coordinates = segments[0]
      return MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
    } else {
      let polylines = segments.map { coords -> MLNPolyline in
        var mutableCoords = coords
        return MLNPolyline(coordinates: &mutableCoords, count: UInt(mutableCoords.count))
      }
      return MLNMultiPolylineFeature(polylines: polylines)
    }
  }

  /// Creates a world-scale polygon feature with interior holes for all saved offline regions.
  /// When rendered by MapLibre, everything outside the saved offline areas is covered by the fill layer.
  static func createOfflineMaskFeature(from state: OfflineMaskVisualState?) -> MLNPolygonFeature? {
    guard let state, state.isActive else { return nil }

    // World-scale exterior ring bounding coordinates covering global Web Mercator extents (EPSG:3857).
    // Conforms to RFC 7946 / MapLibre right-hand rule with strictly Counter-Clockwise (CCW) winding: SW -> SE -> NE -> NW -> SW.
    // Latitude is strictly capped at 85.051128 to stay within Web Mercator mathematical bounds (< 85.0511287798).
    let maxMercatorLat: CLLocationDegrees = 85.051128
    var worldCoordinates: [CLLocationCoordinate2D] = [
      CLLocationCoordinate2D(latitude: -maxMercatorLat, longitude: -180.0), // SW
      CLLocationCoordinate2D(latitude: -maxMercatorLat, longitude: 180.0),  // SE
      CLLocationCoordinate2D(latitude: maxMercatorLat, longitude: 180.0),   // NE
      CLLocationCoordinate2D(latitude: maxMercatorLat, longitude: -180.0),  // NW
      CLLocationCoordinate2D(latitude: -maxMercatorLat, longitude: -180.0)  // SW (closed)
    ]

    let interiorPolygons: [MLNPolygon] = state.offlinePolygons.compactMap { ring in
      guard ring.count >= 4 else { return nil }
      var mutableRing = ring
      return MLNPolygon(coordinates: &mutableRing, count: UInt(mutableRing.count))
    }

    let maskFeature = MLNPolygonFeature(
      coordinates: &worldCoordinates,
      count: UInt(worldCoordinates.count),
      interiorPolygons: interiorPolygons
    )
    maskFeature.attributes = [
      MapFeatureKey.type.rawValue: MapFeatureType.offlineMask.rawValue
    ]
    return maskFeature
  }

  /// Creates polyline features delineating the boundaries of all saved offline regions.
  static func createOfflineRegionsBorderFeature(from state: OfflineMaskVisualState?) -> MLNShape? {
    guard let state, state.isActive, !state.offlinePolygons.isEmpty else { return nil }

    if state.offlinePolygons.count == 1 {
      var coords = state.offlinePolygons[0]
      guard coords.count >= 2 else { return nil }
      let feature = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
      feature.attributes = [MapFeatureKey.type.rawValue: MapFeatureType.offlineRegionsBorder.rawValue]
      return feature
    } else {
      let polylines = state.offlinePolygons.compactMap { ring -> MLNPolyline? in
        guard ring.count >= 2 else { return nil }
        var mutableRing = ring
        return MLNPolyline(coordinates: &mutableRing, count: UInt(mutableRing.count))
      }
      guard !polylines.isEmpty else { return nil }
      let feature = MLNMultiPolylineFeature(polylines: polylines)
      feature.attributes = [MapFeatureKey.type.rawValue: MapFeatureType.offlineRegionsBorder.rawValue]
      return feature
    }
  }
}

