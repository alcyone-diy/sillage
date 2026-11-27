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
    XCTAssertEqual(features.pointFeature?.attributes[MapFeatureKey.status.rawValue] as? String, AnchorVisualStatus.setup.rawValue)
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
    XCTAssertEqual(features.radiusFeature?.attributes[MapFeatureKey.status.rawValue] as? String, AnchorVisualStatus.setup.rawValue)
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
      from: [standardWaypoint, draftWaypoint]
    )

    XCTAssertNotNil(collection)
    guard let features = collection?.shapes as? [MLNPointFeature], features.count == 2 else {
      XCTFail("Expected 2 MLNPointFeature shapes")
      return
    }

    let stdFeature = features[0]
    let draftFeature = features[1]

    XCTAssertEqual(stdFeature.attributes[MapFeatureKey.id.rawValue] as? String, "std-1")
    XCTAssertEqual(draftFeature.attributes[MapFeatureKey.id.rawValue] as? String, "draft-1")
    XCTAssertNil(stdFeature.attributes["isCalloutTarget"])
    XCTAssertNil(draftFeature.attributes["isCalloutTarget"])
  }

  func testCreateGoToWaypointFeature_preservesStandardAttributesWithoutEnlargementFlag() {
    let goTo = WaypointVisualState(
      id: "goto-1",
      name: "GoTo Normal",
      coordinate: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15),
      colorHex: "#007AFF",
      isDraft: false
    )

    let feature = MapLibreFeatureFactory.createGoToWaypointFeature(from: goTo)

    XCTAssertEqual(feature?.attributes[MapFeatureKey.id.rawValue] as? String, "goto-1")
    XCTAssertEqual(feature?.attributes[MapFeatureKey.name.rawValue] as? String, "GoTo Normal")
    XCTAssertEqual(feature?.attributes[MapFeatureKey.color.rawValue] as? String, "#007AFF")
    XCTAssertNil(feature?.attributes["isCalloutTarget"])
  }

  // MARK: - Offline Selection Tests

  func testCreateOfflineSelectionFeature_createsPolygonFeature() {
    let bounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0),
      northEast: CLLocationCoordinate2D(latitude: 48.0, longitude: -2.0)
    )

    let shape = MapLibreFeatureFactory.createOfflineSelectionFeature(from: bounds)
    XCTAssertNotNil(shape)
    guard let polygon = shape as? MLNPolygonFeature else {
      XCTFail("Expected MLNPolygonFeature for offline selection")
      return
    }
    XCTAssertEqual(polygon.pointCount, 5)
    XCTAssertEqual(polygon.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.offlineSelection.rawValue)
  }

  func testCreateOfflineSelectionCornersFeature_creates4PointFeatures() {
    let bounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0),
      northEast: CLLocationCoordinate2D(latitude: 48.0, longitude: -2.0)
    )

    let shape = MapLibreFeatureFactory.createOfflineSelectionCornersFeature(from: bounds)
    XCTAssertNotNil(shape)
    guard let collection = shape as? MLNShapeCollectionFeature,
          let points = collection.shapes as? [MLNPointFeature] else {
      XCTFail("Expected MLNShapeCollectionFeature with MLNPointFeatures for corners")
      return
    }
    XCTAssertEqual(points.count, 4)
    for point in points {
      XCTAssertEqual(point.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.offlineSelectionCorners.rawValue)
    }
  }

  // MARK: - Vessel Feature Tests

  func testCreateVesselFeature_whenNilState_returnsNil() {
    let feature = MapLibreFeatureFactory.createVesselFeature(from: nil)
    XCTAssertNil(feature)
  }

  func testCreateVesselFeature_whenStationaryWithNilCourse_omitsCourseAttribute() {
    let coordinate = CLLocationCoordinate2D(latitude: 46.15, longitude: -1.16)
    let state = VesselVisualState(
      coordinate: coordinate,
      course: nil,
      isStale: false,
      isDegraded: false
    )

    let feature = MapLibreFeatureFactory.createVesselFeature(from: state)

    XCTAssertNotNil(feature)
    XCTAssertEqual(feature?.coordinate.latitude, coordinate.latitude)
    XCTAssertEqual(feature?.coordinate.longitude, coordinate.longitude)
    XCTAssertEqual(feature?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.vessel.rawValue)
    XCTAssertNil(feature?.attributes[MapFeatureKey.course.rawValue])
    XCTAssertEqual(feature?.attributes[MapFeatureKey.isStale.rawValue] as? Bool, false)
    XCTAssertEqual(feature?.attributes[MapFeatureKey.isDegraded.rawValue] as? Bool, false)
  }

  func testCreateVesselFeature_whenMovingWithCourse_setsCourseInDegrees() {
    let coordinate = CLLocationCoordinate2D(latitude: 46.15, longitude: -1.16)
    let state = VesselVisualState(
      coordinate: coordinate,
      course: Measurement(value: 135.0, unit: .degrees),
      isStale: true,
      isDegraded: true
    )

    let feature = MapLibreFeatureFactory.createVesselFeature(from: state)

    XCTAssertNotNil(feature)
    XCTAssertEqual(feature?.coordinate.latitude, coordinate.latitude)
    XCTAssertEqual(feature?.attributes[MapFeatureKey.course.rawValue] as? Double, 135.0)
    XCTAssertEqual(feature?.attributes[MapFeatureKey.isStale.rawValue] as? Bool, true)
    XCTAssertEqual(feature?.attributes[MapFeatureKey.isDegraded.rawValue] as? Bool, true)
  }

  func testCreateAnchorFeatures_whenDraggingWithSwingTrail_attachesStatusToAllFeatures() {
    let anchorCoord = CLLocationCoordinate2D(latitude: 47.218, longitude: -1.553)
    let swing = [
      CLLocationCoordinate2D(latitude: 47.2181, longitude: -1.5531),
      CLLocationCoordinate2D(latitude: 47.2183, longitude: -1.5534)
    ]
    let state = AnchorVisualState(
      status: .dragging,
      pointCoordinate: anchorCoord,
      radius: Measurement(value: 40, unit: .meters),
      vesselCoordinate: swing.last,
      swingCoordinates: swing
    )

    let features = MapLibreFeatureFactory.createAnchorFeatures(from: state)

    XCTAssertEqual(features.pointFeature?.attributes[MapFeatureKey.status.rawValue] as? String, AnchorVisualStatus.dragging.rawValue)
    XCTAssertEqual(features.radiusFeature?.attributes[MapFeatureKey.status.rawValue] as? String, AnchorVisualStatus.dragging.rawValue)
    XCTAssertEqual(features.swingLineFeature?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.anchorSwing.rawValue)
    XCTAssertEqual(features.swingLineFeature?.attributes[MapFeatureKey.status.rawValue] as? String, AnchorVisualStatus.dragging.rawValue)
  }

  // MARK: - Chart Tools Feature Tests

  func testCreateMeasureFeatures_whenInactive_returnsNil() {
    XCTAssertNil(MapLibreFeatureFactory.createMeasureLineFeature(from: .inactive))
    XCTAssertNil(MapLibreFeatureFactory.createMeasurePinsFeature(from: .inactive, activePin: .start))
  }

  func testCreateMeasureFeatures_whenActive_setsStandardizedVocabularyAttributes() {
    let start = CLLocationCoordinate2D(latitude: 46.15, longitude: -1.16)
    let end = CLLocationCoordinate2D(latitude: 46.18, longitude: -1.20)
    let state = MeasureState.active(start: start, end: end)

    let line = MapLibreFeatureFactory.createMeasureLineFeature(from: state)
    XCTAssertEqual(line?.pointCount, 2)
    XCTAssertEqual(line?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.measureLine.rawValue)

    let pinsCollection = MapLibreFeatureFactory.createMeasurePinsFeature(from: state, activePin: .end)
    guard let pins = pinsCollection?.shapes as? [MLNPointFeature], pins.count == 2 else {
      XCTFail("Expected 2 measure pin point features")
      return
    }

    XCTAssertEqual(pins[0].attributes[MapFeatureKey.id.rawValue] as? String, "A")
    XCTAssertEqual(pins[0].attributes[MapFeatureKey.icon.rawValue] as? String, "measure-pin-a-idle")
    XCTAssertEqual(pins[0].attributes[MapFeatureKey.sortKey.rawValue] as? Int, 1)

    XCTAssertEqual(pins[1].attributes[MapFeatureKey.id.rawValue] as? String, "B")
    XCTAssertEqual(pins[1].attributes[MapFeatureKey.icon.rawValue] as? String, "measure-pin-b-selected")
    XCTAssertEqual(pins[1].attributes[MapFeatureKey.sortKey.rawValue] as? Int, 2)
  }

  func testCreateTargetAimingCrosshairFeature_handlesOptionalCoordinate() {
    XCTAssertNil(MapLibreFeatureFactory.createTargetAimingCrosshairFeature(from: nil))

    let coord = CLLocationCoordinate2D(latitude: 46.15, longitude: -1.16)
    let feature = MapLibreFeatureFactory.createTargetAimingCrosshairFeature(from: coord)
    XCTAssertEqual(feature?.coordinate.latitude, coord.latitude)
    XCTAssertEqual(feature?.coordinate.longitude, coord.longitude)
    XCTAssertEqual(feature?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.targetAimingCrosshair.rawValue)
  }
}
