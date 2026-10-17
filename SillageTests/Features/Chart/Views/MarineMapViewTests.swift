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

  func testAimingCrosshairAnchoringForOneFingerZoom() {
    let mapView = MarineMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
    final class CrosshairState {
      var isDisplayed: Bool = true
    }
    let state = CrosshairState()

    mapView.customGestureAnchorProvider = { [weak mapView, weak state] gesture in
      guard let mapView, state?.isDisplayed == true else { return nil }
      if gesture is UILongPressGestureRecognizer {
        return CGPoint(
          x: mapView.bounds.midX,
          y: mapView.bounds.height * AppConstants.Map.aimingCrosshairYFraction
        )
      }
      if let tapGesture = gesture as? UITapGestureRecognizer {
        let isDoubleTapZoomIn = tapGesture.numberOfTapsRequired == 2 && tapGesture.numberOfTouchesRequired == 1
        let isTwoFingerTapZoomOut = tapGesture.numberOfTapsRequired == 1 && tapGesture.numberOfTouchesRequired == 2
        if isDoubleTapZoomIn || isTwoFingerTapZoomOut {
          return CGPoint(
            x: mapView.bounds.midX,
            y: mapView.bounds.height * AppConstants.Map.aimingCrosshairYFraction
          )
        }
      }
      return nil
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

    let expectedAimingPoint = CGPoint(
      x: 150.0,
      y: 600.0 * AppConstants.Map.aimingCrosshairYFraction
    )

    // 1. Quick zoom (one-finger zoom) anchors on aiming crosshair
    XCTAssertEqual(mapView.anchorPoint(forGesture: quickZoomGesture), expectedAimingPoint)

    // 2. Double-tap zoom-in anchors on aiming crosshair
    XCTAssertEqual(mapView.anchorPoint(forGesture: doubleTapGesture), expectedAimingPoint)

    // 3. Two-finger tap zoom-out anchors on aiming crosshair
    XCTAssertEqual(mapView.anchorPoint(forGesture: twoFingerTapGesture), expectedAimingPoint)

    // 4. Single-tap falls back to default MapLibre behavior
    let singleTapAnchor = mapView.anchorPoint(forGesture: singleTapGesture)
    XCTAssertNotEqual(singleTapAnchor, expectedAimingPoint)

    // 5. Pinch gesture falls back to default MapLibre behavior
    let pinchAnchor = mapView.anchorPoint(forGesture: pinchGesture)
    XCTAssertNotEqual(pinchAnchor, expectedAimingPoint)

    // 6. When crosshair is NOT displayed, quick zoom falls back to default MapLibre behavior
    state.isDisplayed = false
    let fallbackAnchor = mapView.anchorPoint(forGesture: quickZoomGesture)
    XCTAssertNotEqual(fallbackAnchor, expectedAimingPoint)
  }
}
