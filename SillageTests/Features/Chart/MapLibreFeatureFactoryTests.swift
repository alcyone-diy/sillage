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
}
