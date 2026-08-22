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

  func testCreateOfflineMaskFeature_whenNilOrInactive_returnsNil() {
    XCTAssertNil(MapLibreFeatureFactory.createOfflineMaskFeature(from: nil))

    let inactiveState = OfflineMaskVisualState(isActive: false, offlinePolygons: [])
    XCTAssertNil(MapLibreFeatureFactory.createOfflineMaskFeature(from: inactiveState))
  }

  func testCreateOfflineMaskFeature_whenActiveWithNoPolygons_returnsWorldPolygonWithoutHoles() {
    let state = OfflineMaskVisualState(isActive: true, offlinePolygons: [])
    let feature = MapLibreFeatureFactory.createOfflineMaskFeature(from: state)

    XCTAssertNotNil(feature)
    XCTAssertEqual(feature?.pointCount, 5)
    XCTAssertEqual(feature?.interiorPolygons?.count ?? 0, 0)
    XCTAssertEqual(feature?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.offlineMask.rawValue)

    // Verify RFC 7946 Counter-Clockwise (CCW) winding: SW -> SE -> NE -> NW -> SW
    var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: 5)
    feature?.getCoordinates(&coords, range: NSRange(location: 0, length: 5))

    // SW
    XCTAssertEqual(coords[0].latitude, -85.051128, accuracy: 1e-6)
    XCTAssertEqual(coords[0].longitude, -180.0, accuracy: 1e-6)
    // SE
    XCTAssertEqual(coords[1].latitude, -85.051128, accuracy: 1e-6)
    XCTAssertEqual(coords[1].longitude, 180.0, accuracy: 1e-6)
    // NE
    XCTAssertEqual(coords[2].latitude, 85.051128, accuracy: 1e-6)
    XCTAssertEqual(coords[2].longitude, 180.0, accuracy: 1e-6)
    // NW
    XCTAssertEqual(coords[3].latitude, 85.051128, accuracy: 1e-6)
    XCTAssertEqual(coords[3].longitude, -180.0, accuracy: 1e-6)
    // SW (closed)
    XCTAssertEqual(coords[4].latitude, -85.051128, accuracy: 1e-6)
    XCTAssertEqual(coords[4].longitude, -180.0, accuracy: 1e-6)
  }

  func testCreateOfflineMaskFeature_whenActiveWithPolygons_returnsWorldPolygonWithInteriorHoles() {
    let hole1 = [
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.5),
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0),
      CLLocationCoordinate2D(latitude: 47.0, longitude: -1.0),
      CLLocationCoordinate2D(latitude: 47.0, longitude: -1.5),
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.5)
    ]
    let state = OfflineMaskVisualState(isActive: true, offlinePolygons: [hole1])
    let feature = MapLibreFeatureFactory.createOfflineMaskFeature(from: state)

    XCTAssertNotNil(feature)
    XCTAssertEqual(feature?.interiorPolygons?.count, 1)
    XCTAssertEqual(feature?.interiorPolygons?.first?.pointCount, 5)
  }

  func testCreateOfflineRegionsBorderFeature_whenSinglePolygon_returnsPolylineFeature() {
    let ring = [
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.5),
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0),
      CLLocationCoordinate2D(latitude: 47.0, longitude: -1.0),
      CLLocationCoordinate2D(latitude: 47.0, longitude: -1.5),
      CLLocationCoordinate2D(latitude: 46.0, longitude: -1.5)
    ]
    let state = OfflineMaskVisualState(isActive: true, offlinePolygons: [ring])
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
    let state = OfflineMaskVisualState(isActive: true, offlinePolygons: [ring1, ring2])
    let shape = MapLibreFeatureFactory.createOfflineRegionsBorderFeature(from: state)

    XCTAssertTrue(shape is MLNMultiPolylineFeature)
    let multiPolyline = shape as? MLNMultiPolylineFeature
    XCTAssertEqual(multiPolyline?.polylines.count, 2)
    XCTAssertEqual(multiPolyline?.attributes[MapFeatureKey.type.rawValue] as? String, MapFeatureType.offlineRegionsBorder.rawValue)
  }
}
