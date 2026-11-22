//
//  WaypointMagneticSnapTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

final class WaypointMagneticSnapTests: XCTestCase {

  private let reticle = CGPoint(x: 200, y: 300)

  func testAttachWhenWithinSnapRadius() {
    let wpCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    let candidate = WaypointSnapCandidate(
      id: "wp-1",
      coordinate: wpCoord,
      screenPoint: CGPoint(x: 210, y: 305) // dist ~11.18 <= 16
    )

    let result = WaypointMagneticSnap.evaluate(
      reticlePoint: reticle,
      candidates: [candidate],
      currentlySnappedID: nil,
      attachRadius: 16,
      detachHysteresis: 6
    )

    XCTAssertEqual(result?.waypointID, "wp-1")
    XCTAssertEqual(result?.coordinate.latitude, wpCoord.latitude)
    XCTAssertEqual(result?.coordinate.longitude, wpCoord.longitude)
    XCTAssertEqual(result?.visualOffset.width ?? 0, 10, accuracy: 0.001)
    XCTAssertEqual(result?.visualOffset.height ?? 0, 5, accuracy: 0.001)
  }

  func testDoesNotAttachOutsideSnapRadius() {
    let candidate = WaypointSnapCandidate(
      id: "wp-1",
      coordinate: CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0),
      screenPoint: CGPoint(x: 217, y: 300) // dist 17 > 16
    )

    let result = WaypointMagneticSnap.evaluate(
      reticlePoint: reticle,
      candidates: [candidate],
      currentlySnappedID: nil,
      attachRadius: 16,
      detachHysteresis: 6
    )

    XCTAssertNil(result)
  }

  func testHysteresisKeepsLockUntilDetachRadiusExceeded() {
    let wpCoord = CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0)
    let withinHysteresis = WaypointSnapCandidate(
      id: "wp-1",
      coordinate: wpCoord,
      screenPoint: CGPoint(x: 220, y: 300) // dist 20: > 16 attach, <= 22 detach
    )

    let kept = WaypointMagneticSnap.evaluate(
      reticlePoint: reticle,
      candidates: [withinHysteresis],
      currentlySnappedID: "wp-1",
      attachRadius: 16,
      detachHysteresis: 6
    )

    XCTAssertEqual(kept?.waypointID, "wp-1")
    XCTAssertEqual(kept?.visualOffset.width ?? 0, 20, accuracy: 0.001)

    let beyondHysteresis = WaypointSnapCandidate(
      id: "wp-1",
      coordinate: wpCoord,
      screenPoint: CGPoint(x: 223, y: 300) // dist 23 > 22 detach
    )

    let detached = WaypointMagneticSnap.evaluate(
      reticlePoint: reticle,
      candidates: [beyondHysteresis],
      currentlySnappedID: "wp-1",
      attachRadius: 16,
      detachHysteresis: 6
    )

    XCTAssertNil(detached)
  }

  func testSelectsClosestWaypointWhenMultipleWithinAttachRadius() {
    let farCandidate = WaypointSnapCandidate(
      id: "wp-far",
      coordinate: CLLocationCoordinate2D(latitude: 47.01, longitude: -3.01),
      screenPoint: CGPoint(x: 214, y: 300) // dist 14
    )
    let nearCandidate = WaypointSnapCandidate(
      id: "wp-near",
      coordinate: CLLocationCoordinate2D(latitude: 47.02, longitude: -3.02),
      screenPoint: CGPoint(x: 205, y: 300) // dist 5
    )

    let result = WaypointMagneticSnap.evaluate(
      reticlePoint: reticle,
      candidates: [farCandidate, nearCandidate],
      currentlySnappedID: nil,
      attachRadius: 16,
      detachHysteresis: 6
    )

    XCTAssertEqual(result?.waypointID, "wp-near")
  }

  func testDoesNotTransferLockWhenOtherWaypointIsWithinHysteresisMargin() {
    let currentCandidate = WaypointSnapCandidate(
      id: "wp-current",
      coordinate: CLLocationCoordinate2D(latitude: 47.01, longitude: -3.01),
      screenPoint: CGPoint(x: 215, y: 300) // dist 15 (locked)
    )
    let slightlyCloserCandidate = WaypointSnapCandidate(
      id: "wp-neighbor",
      coordinate: CLLocationCoordinate2D(latitude: 47.02, longitude: -3.02),
      screenPoint: CGPoint(x: 211, y: 300) // dist 11: 11 + 6 = 17 >= 15 -> must NOT steal lock
    )

    let result = WaypointMagneticSnap.evaluate(
      reticlePoint: reticle,
      candidates: [currentCandidate, slightlyCloserCandidate],
      currentlySnappedID: "wp-current",
      attachRadius: 16,
      detachHysteresis: 6
    )

    XCTAssertEqual(result?.waypointID, "wp-current")
  }

  func testTransfersLockToCloserWaypointInsideAttachRadius() {
    let currentCandidate = WaypointSnapCandidate(
      id: "wp-current",
      coordinate: CLLocationCoordinate2D(latitude: 47.01, longitude: -3.01),
      screenPoint: CGPoint(x: 218, y: 300) // dist 18 (inside hysteresis)
    )
    let closerCandidate = WaypointSnapCandidate(
      id: "wp-closer",
      coordinate: CLLocationCoordinate2D(latitude: 47.02, longitude: -3.02),
      screenPoint: CGPoint(x: 204, y: 300) // dist 4: 4 + 6 = 10 < 18 -> decisively closer
    )

    let result = WaypointMagneticSnap.evaluate(
      reticlePoint: reticle,
      candidates: [currentCandidate, closerCandidate],
      currentlySnappedID: "wp-current",
      attachRadius: 16,
      detachHysteresis: 6
    )

    XCTAssertEqual(result?.waypointID, "wp-closer")
  }
}
