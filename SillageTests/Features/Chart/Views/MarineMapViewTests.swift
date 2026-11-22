//
//  MarineMapViewTests.swift
//  SillageTests
//
//  Created by Alcyone on 2026-10-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import UIKit
import MapLibre
@testable import Sillage

@MainActor
final class MarineMapViewTests: XCTestCase {

  func testDefaultBehaviorWithoutCustomAnchorProvider() {
    let mapView = MarineMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
    let gesture = UIPanGestureRecognizer()
    mapView.addGestureRecognizer(gesture)

    let anchor = mapView.anchorPoint(forGesture: gesture)
    XCTAssertFalse(anchor.x.isNaN)
    XCTAssertFalse(anchor.y.isNaN)
  }

  func testCustomAnchorProviderOverridesAnchorPoint() {
    let mapView = MarineMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
    let gesture = UILongPressGestureRecognizer()
    mapView.addGestureRecognizer(gesture)

    let expectedPoint = CGPoint(x: 150, y: 200)
    mapView.customGestureAnchorProvider = { _ in
      expectedPoint
    }

    let anchor = mapView.anchorPoint(forGesture: gesture)
    XCTAssertEqual(anchor, expectedPoint)
  }

  func testAimingCrosshairAnchoringForAllZoomGestures() {
    let mapView = MarineMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
    final class CrosshairState {
      var yFraction: CGFloat? = AppConstants.Map.aimingCrosshairYFraction
    }
    let state = CrosshairState()

    mapView.customGestureAnchorProvider = { [weak mapView, weak state] gesture in
      guard let mapView else { return nil }
      return MarineMapView.zoomAnchorPoint(
        for: gesture,
        in: mapView.bounds,
        crosshairYFraction: state?.yFraction
      )
    }

    let quickZoomGesture = UILongPressGestureRecognizer()
    let doubleTapGesture = UITapGestureRecognizer()
    doubleTapGesture.numberOfTapsRequired = 2
    doubleTapGesture.numberOfTouchesRequired = 1

    let twoFingerTapGesture = UITapGestureRecognizer()
    twoFingerTapGesture.numberOfTapsRequired = 1
    twoFingerTapGesture.numberOfTouchesRequired = 2

    let singleTapGesture = UITapGestureRecognizer()
    singleTapGesture.numberOfTapsRequired = 1
    singleTapGesture.numberOfTouchesRequired = 1

    let pinchGesture = UIPinchGestureRecognizer()
    let panGesture = UIPanGestureRecognizer()

    let expectedCalloutPoint = CGPoint(
      x: 150.0,
      y: 600.0 * AppConstants.Map.aimingCrosshairYFraction
    )

    // 1. All zoom gestures (quick zoom, double-tap, two-finger tap, pinch) anchor on callout crosshair (40%)
    XCTAssertEqual(mapView.anchorPoint(forGesture: quickZoomGesture), expectedCalloutPoint)
    XCTAssertEqual(mapView.anchorPoint(forGesture: doubleTapGesture), expectedCalloutPoint)
    XCTAssertEqual(mapView.anchorPoint(forGesture: twoFingerTapGesture), expectedCalloutPoint)
    XCTAssertEqual(mapView.anchorPoint(forGesture: pinchGesture), expectedCalloutPoint)

    // 2. Non-zoom gestures fall back to default MapLibre behavior
    XCTAssertNotEqual(mapView.anchorPoint(forGesture: singleTapGesture), expectedCalloutPoint)
    XCTAssertNotEqual(mapView.anchorPoint(forGesture: panGesture), expectedCalloutPoint)

    // 3. Position picker HUDs (WaypointAdjustHUD, AnchorAdjustHUD, AnchorDropHUD) anchor at 50% center
    state.yFraction = AppConstants.Map.positionPickerCrosshairYFraction
    let expectedPickerPoint = CGPoint(
      x: 150.0,
      y: 600.0 * AppConstants.Map.positionPickerCrosshairYFraction
    )
    XCTAssertEqual(mapView.anchorPoint(forGesture: quickZoomGesture), expectedPickerPoint)
    XCTAssertEqual(mapView.anchorPoint(forGesture: doubleTapGesture), expectedPickerPoint)
    XCTAssertEqual(mapView.anchorPoint(forGesture: twoFingerTapGesture), expectedPickerPoint)
    XCTAssertEqual(mapView.anchorPoint(forGesture: pinchGesture), expectedPickerPoint)

    // 4. When no crosshair is displayed, all zoom gestures fall back to default MapLibre behavior
    state.yFraction = nil
    XCTAssertNotEqual(mapView.anchorPoint(forGesture: quickZoomGesture), expectedCalloutPoint)
    XCTAssertNotEqual(mapView.anchorPoint(forGesture: pinchGesture), expectedPickerPoint)
  }
}
