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
    
    guard !segments.isEmpty else { return nil }
    
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
}

