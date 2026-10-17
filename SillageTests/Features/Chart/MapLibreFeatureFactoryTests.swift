//
//  MapLibreFeatureFactoryTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
import MapLibre
@testable import Sillage

@MainActor
final class MapLibreFeatureFactoryTests: XCTestCase {

  func testCreateAnchorFeatures_whenNilState_returnsNilFeatures() {
    let features = MapLibreFeatureFactory.createAnchorFeatures(from: nil)

    XCTAssertNil(features.pointFeature)
    XCTAssertNil(features.radiusFeature)
    XCTAssertNil(features.rodeLineFeature)
  }

  func testCreateAnchorFeatures_whenSetupStatus_returnsPointOnly() {
    let anchorCoord = CLLocationCoordinate2D(latitude: 47.218, longitude: -1.553)
    let state = AnchorVisualState(
      status: .setup,
      pointCoordinate: anchorCoord,
      radius: nil,
      vesselCoordinate: nil
    )

    let features = MapLibreFeatureFactory.createAnchorFeatures(from: state)

    XCTAssertNotNil(features.pointFeature)
    XCTAssertEqual(features.pointFeature?.coordinate.latitude, anchorCoord.latitude)
    XCTAssertNil(features.radiusFeature)
    XCTAssertNil(features.rodeLineFeature)
  }

  func testCreateAnchorFeatures_whenSetupStatusWithRadius_returnsPointAndRadius() {
    let anchorCoord = CLLocationCoordinate2D(latitude: 47.218, longitude: -1.553)
    let state = AnchorVisualState(
      status: .setup,
      pointCoordinate: anchorCoord,
      radius: Measurement(value: 50, unit: .meters),
      vesselCoordinate: nil
    )

    let features = MapLibreFeatureFactory.createAnchorFeatures(from: state)

    XCTAssertNotNil(features.pointFeature)
    XCTAssertNotNil(features.radiusFeature)
    XCTAssertNil(features.rodeLineFeature)
  }

  func testCreateAnchorFeatures_whenDroppedStatusWithVessel_returnsPointRadiusAndRodeLine() {
    let anchorCoord = CLLocationCoordinate2D(latitude: 47.218, longitude: -1.553)
    let vesselCoord = CLLocationCoordinate2D(latitude: 47.219, longitude: -1.554)
    let state = AnchorVisualState(
      status: .dropped,
      pointCoordinate: anchorCoord,
      radius: Measurement(value: 30, unit: .meters),
      vesselCoordinate: vesselCoord
    )

    let features = MapLibreFeatureFactory.createAnchorFeatures(from: state)

    XCTAssertNil(features.rodeLineFeature)
  }


  func testCreateAnchorFeatures_whenArmedStatusWithoutVessel_returnsPointAndRadiusOnly() {
    let anchorCoord = CLLocationCoordinate2D(latitude: 47.218, longitude: -1.553)
    let state = AnchorVisualState(
      status: .armed,
      pointCoordinate: anchorCoord,
      radius: Measurement(value: 50, unit: .meters),
      vesselCoordinate: nil
    )

    let features = MapLibreFeatureFactory.createAnchorFeatures(from: state)

    XCTAssertNotNil(features.pointFeature)
    XCTAssertNotNil(features.radiusFeature)
    XCTAssertNil(features.rodeLineFeature)
  }

  // MARK: - Offline Mask Tests

  func testCreateOfflineMaskFeature_whenNilOrInactiveOrEmpty_returnsNil() {
    XCTAssertNil(MapLibreFeatureFactory.createOfflineMaskFeature(from: nil))

    let inactiveState = OfflineMaskVisualState(isActive: false, maskHoles: [], savedOfflinePolygons: [])
    XCTAssertNil(MapLibreFeatureFactory.createOfflineMaskFeature(from: inactiveState))

    let activeEmptyState = OfflineMaskVisualState(isActive: true, maskHoles: [], savedOfflinePolygons: [])
    XCTAssertNil(MapLibreFeatureFactory.createOfflineMaskFeature(from: activeEmptyState))
  }

  func testCreateOfflineMaskFeature_whenSinglePolygon_returnsPolygonFeature() {
    let ring = [
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.5),
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0),
      CLLocationCoordinate2D(latitude: 47.0, longitude: -1.0),
      CLLocationCoordinate2D(latitude: 47.0, longitude: -1.5),
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.5)
    ]
    let state = OfflineMaskVisualState(isActive: true, maskHoles: [], savedOfflinePolygons: [ring])
    let shape = MapLibreFeatureFactory.createOfflineMaskFeature(from: state)

    XCTAssertTrue(shape is MLNPolygonFeature)
    let polygon = shape as? MLNPolygonFeature
    XCTAssertEqual(polygon?.pointCount, 5)
    XCTAssertEqual(polygon?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.offlineMask.rawValue)
  }

  func testCreateOfflineMaskFeature_whenMultiplePolygons_returnsShapeCollectionFeature() {
    let ring1 = [
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.5),
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0),
      CLLocationCoordinate2D(latitude: 47.0, longitude: -1.0),
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.5)
    ]
    let ring2 = [
      CLLocationCoordinate2D(latitude: 48.0, longitude: -2.5),
      CLLocationCoordinate2D(latitude: 48.0, longitude: -2.0),
      CLLocationCoordinate2D(latitude: 49.0, longitude: -2.0),
      CLLocationCoordinate2D(latitude: 48.0, longitude: -2.5)
    ]
    let state = OfflineMaskVisualState(isActive: true, maskHoles: [], savedOfflinePolygons: [ring1, ring2])
    let shape = MapLibreFeatureFactory.createOfflineMaskFeature(from: state)

    XCTAssertTrue(shape is MLNShapeCollectionFeature)
    let collection = shape as? MLNShapeCollectionFeature
    XCTAssertEqual(collection?.shapes.count, 2)
    let poly1 = collection?.shapes[0] as? MLNPolygonFeature
    let poly2 = collection?.shapes[1] as? MLNPolygonFeature
    XCTAssertEqual(poly1?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.offlineMask.rawValue)
    XCTAssertEqual(poly2?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.offlineMask.rawValue)
  }

  func testCreateOfflineRegionsBorderFeature_whenSinglePolygon_returnsPolylineFeature() {
    let ring = [
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.5),
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0),
      CLLocationCoordinate2D(latitude: 47.0, longitude: -1.0),
      CLLocationCoordinate2D(latitude: 47.0, longitude: -1.5),
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.5)
    ]
    let state = OfflineMaskVisualState(isActive: true, maskHoles: [], savedOfflinePolygons: [ring])
    let shape = MapLibreFeatureFactory.createOfflineRegionsBorderFeature(from: state)

    XCTAssertTrue(shape is MLNPolylineFeature)
    let polyline = shape as? MLNPolylineFeature
    XCTAssertEqual(polyline?.pointCount, 5)
    XCTAssertEqual(polyline?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.offlineRegionsBorder.rawValue)
  }

  func testCreateOfflineRegionsBorderFeature_whenMultiplePolygons_returnsMultiPolylineFeature() {
    let ring1 = [
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.5),
      CLLocationCoordinate2D(latitude: 47.0, longitude: -1.5)
    ]
    let ring2 = [
      CLLocationCoordinate2D(latitude: 48.0, longitude: -2.5),
      CLLocationCoordinate2D(latitude: 49.0, longitude: -2.5)
    ]
    let state = OfflineMaskVisualState(isActive: true, maskHoles: [], savedOfflinePolygons: [ring1, ring2])
    let shape = MapLibreFeatureFactory.createOfflineRegionsBorderFeature(from: state)

    XCTAssertTrue(shape is MLNMultiPolylineFeature)
    let multiPolyline = shape as? MLNMultiPolylineFeature
    XCTAssertEqual(multiPolyline?.polylines.count, 2)
    XCTAssertEqual(multiPolyline?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.offlineRegionsBorder.rawValue)
  }

  func testCreateOfflineHighlightFeature_returnsPolygonFeatureWithOfflineHighlightType() {
    let bounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0),
      northEast: CLLocationCoordinate2D(latitude: 48.0, longitude: -2.0)
    )
    let shape = MapLibreFeatureFactory.createOfflineHighlightFeature(from: bounds)

    XCTAssertTrue(shape is MLNPolygonFeature)
    let polygon = shape as? MLNPolygonFeature
    XCTAssertEqual(polygon?.pointCount, 5)
    XCTAssertEqual(polygon?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.offlineHighlight.rawValue)
  }

  func testCreateVisibleWaypointsFeature_whenDraft_setsIsCalloutTargetTrue() {
    let standardWaypoint = WaypointVisualState(
      id: "std-1",
      name: "Saved Point",
      coordinate: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15),
      colorHex: "#007AFF",
      isDraft: false
    )
    let draftWaypoint = WaypointVisualState(
      id: "draft-1",
      name: "Draft Point",
      coordinate: CLLocationCoordinate2D(latitude: 46.20, longitude: -1.20),
      colorHex: "#FF9500",
      isDraft: true
    )

    let collection = MapLibreFeatureFactory.createVisibleWaypointsFeature(
      from: [standardWaypoint, draftWaypoint],
      targetWaypointID: nil
    )

    XCTAssertNotNil(collection)
    guard let features = collection?.shapes as? [MLNPointFeature], features.count == 2 else {
      XCTFail("Expected 2 MLNPointFeature shapes")
      return
    }

    let stdFeature = features[0]
    let draftFeature = features[1]

    XCTAssertEqual(stdFeature.attributes["isCalloutTarget"] as? Bool, false)
    XCTAssertEqual(draftFeature.attributes["isCalloutTarget"] as? Bool, true)
  }

  func testCreateVisibleWaypointsFeature_whenSelected_setsIsCalloutTargetTrue() {
    let standardWaypoint = WaypointVisualState(
      id: "std-1",
      name: "Saved Point",
      coordinate: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15),
      colorHex: "#007AFF",
      isDraft: false,
      isSelected: false
    )
    let selectedWaypoint = WaypointVisualState(
      id: "edit-1",
      name: "Editing Point",
      coordinate: CLLocationCoordinate2D(latitude: 46.20, longitude: -1.20),
      colorHex: "#FF9500",
      isDraft: false,
      isSelected: true
    )

    let collection = MapLibreFeatureFactory.createVisibleWaypointsFeature(
      from: [standardWaypoint, selectedWaypoint],
      targetWaypointID: nil
    )

    XCTAssertNotNil(collection)
    guard let features = collection?.shapes as? [MLNPointFeature], features.count == 2 else {
      XCTFail("Expected 2 MLNPointFeature shapes")
      return
    }

    XCTAssertEqual(features[0].attributes["isCalloutTarget"] as? Bool, false)
    XCTAssertEqual(features[1].attributes["isCalloutTarget"] as? Bool, true)
  }

  func testCreateGoToWaypointFeature_whenSelected_setsIsCalloutTargetTrue() {
    let unselectedGoTo = WaypointVisualState(
      id: "goto-1",
      name: "GoTo Normal",
      coordinate: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15),
      colorHex: "#007AFF",
      isDraft: false,
      isSelected: false
    )
    let selectedGoTo = WaypointVisualState(
      id: "goto-2",
      name: "GoTo Editing",
      coordinate: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15),
      colorHex: "#007AFF",
      isDraft: false,
      isSelected: true
    )

    let feature1 = MapLibreFeatureFactory.createGoToWaypointFeature(from: unselectedGoTo, targetWaypointID: nil)
    let feature2 = MapLibreFeatureFactory.createGoToWaypointFeature(from: selectedGoTo, targetWaypointID: nil)

    XCTAssertEqual(feature1?.attributes["isCalloutTarget"] as? Bool, false)
    XCTAssertEqual(feature2?.attributes["isCalloutTarget"] as? Bool, true)
  }
}
