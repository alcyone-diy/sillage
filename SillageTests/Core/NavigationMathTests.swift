//
//  NavigationMathTests.swift
//  SillageTests
//
//  Created by Alcyone on 2026-11-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

final class NavigationMathTests: XCTestCase {

  // MARK: - WGS-84 Vincenty Geodesic Distance

  func testVincentyMatchesPublishedFlindersPeakToBuninyongBenchmark() {
    // Classic geodetic benchmark from Vincenty (1975) / Geoscience Australia on WGS-84:
    // Flinders Peak (37°57'03.72030"S, 144°25'29.52440"E) -> Buninyong (37°39'10.15610"S, 143°55'35.38390"E)
    // Published WGS-84 ellipsoidal distance: 54,972.271 m
    let flindersPeak = CLLocationCoordinate2D(
      latitude: -(37.0 + 57.0 / 60.0 + 3.72030 / 3600.0),
      longitude: 144.0 + 25.0 / 60.0 + 29.52440 / 3600.0
    )
    let buninyong = CLLocationCoordinate2D(
      latitude: -(37.0 + 39.0 / 60.0 + 10.15610 / 3600.0),
      longitude: 143.0 + 55.0 / 60.0 + 35.38390 / 3600.0
    )

    let distanceMeters = flindersPeak.distance(to: buninyong).converted(to: .meters).value
    XCTAssertEqual(distanceMeters, 54_972.271, accuracy: 0.005)
  }

  func testVincentyMatchesReferenceVectorsAndCoreLocationEnvelopeAcrossMaritimeScales() {
    // Exact WGS-84 ellipsoidal reference distances (sub-millimeter precision) paired with a sanity check
    // against CoreLocation's CLLocation.distance(from:), whose legacy approximation drifts by up to ~0.4%
    // from true WGS-84 geodesics (e.g., 111,598.09 m in CoreLocation vs 111,207.10 m exact WGS-84).
    let vectors: [(name: String, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D, exactWGS84Meters: Double)] = [
      (
        "Anchor swing in La Rochelle (~47 m)",
        CLLocationCoordinate2D(latitude: 46.147200, longitude: -1.168400),
        CLLocationCoordinate2D(latitude: 46.147550, longitude: -1.168050),
        47.378106
      ),
      (
        "Coastal passage La Rochelle -> Ile d'Yeu (~111 km)",
        CLLocationCoordinate2D(latitude: 46.1472, longitude: -1.1684),
        CLLocationCoordinate2D(latitude: 46.7258, longitude: -2.3489),
        111_207.096448
      ),
      (
        "Transatlantic passage Brest -> Pointe-a-Pitre (~6,255 km)",
        CLLocationCoordinate2D(latitude: 48.3830, longitude: -4.4860),
        CLLocationCoordinate2D(latitude: 16.2410, longitude: -61.5330),
        6_255_253.887970
      ),
      (
        "Pacific anti-meridian crossing (179.5°E -> 179.5°W)",
        CLLocationCoordinate2D(latitude: -16.8000, longitude: 179.5000),
        CLLocationCoordinate2D(latitude: -16.8500, longitude: -179.5000),
        106_727.583214
      )
    ]

    for entry in vectors {
      let computedMeters = entry.a.distance(to: entry.b).converted(to: .meters).value
      XCTAssertEqual(
        computedMeters,
        entry.exactWGS84Meters,
        accuracy: 0.001,
        "Sub-millimeter WGS-84 mismatch on \(entry.name)"
      )

      let clStart = CLLocation(latitude: entry.a.latitude, longitude: entry.a.longitude)
      let clEnd = CLLocation(latitude: entry.b.latitude, longitude: entry.b.longitude)
      let clMeters = clStart.distance(from: clEnd)
      XCTAssertEqual(
        computedMeters,
        clMeters,
        accuracy: max(0.5, entry.exactWGS84Meters * 0.005),
        "Unexpected divergence from CoreLocation envelope on \(entry.name)"
      )
    }
  }

  func testEquatorialGeodesicGuardMatchesExactEquatorialArc() {
    // Along the equator (lat = 0), cos2Alpha == 0 triggers the equatorial guard (cos2SigmaM = 0).
    // Exact WGS-84 equatorial arc for 30° of longitude = (30 / 360) * 2 * pi * a.
    let origin = CLLocationCoordinate2D(latitude: 0.0, longitude: -10.0)
    let destination = CLLocationCoordinate2D(latitude: 0.0, longitude: 20.0)

    let expectedMeters = (30.0 / 360.0) * 2.0 * .pi * GeodesicConstants.WGS84.semiMajorAxis.converted(to: .meters).value
    let computedMeters = origin.distance(to: destination).converted(to: .meters).value

    XCTAssertEqual(computedMeters, expectedMeters, accuracy: 0.01)
    // Verify it differs from spherical Haversine (~3,335.85 km vs 3,339.58 km -> ~3.7 km difference)
    let sphericalMeters = origin.haversineDistance(to: destination).converted(to: .meters).value
    XCTAssertGreaterThan(abs(computedMeters - sphericalMeters), 3_500.0)
  }

  func testNavigationFixDistanceUsesUnifiedGeodesicMath() {
    let fixA = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 46.1472, longitude: -1.1684),
      horizontalAccuracy: Measurement(value: 3.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date(timeIntervalSince1970: 1_000)
    )
    let fixB = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 46.2000, longitude: -1.2500),
      horizontalAccuracy: Measurement(value: 3.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date(timeIntervalSince1970: 1_060)
    )

    XCTAssertEqual(
      fixA.distance(from: fixB).converted(to: .meters).value,
      fixA.coordinate.distance(to: fixB.coordinate).converted(to: .meters).value,
      accuracy: 1e-9
    )
  }

  func testVincentyEdgeCasesCoincidentAntiMeridianPolesAntipodesAndNonFinite() {
    // 1. Identical coordinates -> exact 0
    let laRochelle = CLLocationCoordinate2D(latitude: 46.1472, longitude: -1.1684)
    XCTAssertEqual(laRochelle.distance(to: laRochelle).converted(to: .meters).value, 0.0)

    // 2. Anti-meridian alias (+180° and -180° at same latitude) -> exact 0
    let east180 = CLLocationCoordinate2D(latitude: 12.5, longitude: 180.0)
    let west180 = CLLocationCoordinate2D(latitude: 12.5, longitude: -180.0)
    XCTAssertEqual(east180.distance(to: west180).converted(to: .meters).value, 0.0)

    // 3. Coincident North Pole with distinct longitudes -> exact 0
    let poleA = CLLocationCoordinate2D(latitude: 90.0, longitude: 15.0)
    let poleB = CLLocationCoordinate2D(latitude: 90.0, longitude: -140.0)
    XCTAssertEqual(poleA.distance(to: poleB).converted(to: .meters).value, 0.0)

    // 4. Exact antipodes & near-antipodal non-converging pair -> finite Haversine fallback (> 19,900 km)
    let northPole = CLLocationCoordinate2D(latitude: 90.0, longitude: 0.0)
    let southPole = CLLocationCoordinate2D(latitude: -90.0, longitude: 0.0)
    let poleToPole = northPole.distance(to: southPole).converted(to: .meters).value
    XCTAssertTrue(poleToPole.isFinite)
    XCTAssertGreaterThan(poleToPole, 20_000_000.0)

    let eqOrigin = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
    let eqAntipode = CLLocationCoordinate2D(latitude: 0.0, longitude: 180.0)
    let eqAntipodeMeters = eqOrigin.distance(to: eqAntipode).converted(to: .meters).value
    XCTAssertTrue(eqAntipodeMeters.isFinite)
    XCTAssertGreaterThan(eqAntipodeMeters, 20_000_000.0)

    // Classic Vincenty non-convergence pair near antipodes: (0°, 0°) -> (0.5°, 179.7°)
    let nearAntipode = CLLocationCoordinate2D(latitude: 0.5, longitude: 179.7)
    let nearAntipodeMeters = eqOrigin.distance(to: nearAntipode).converted(to: .meters).value
    XCTAssertTrue(nearAntipodeMeters.isFinite)
    XCTAssertGreaterThan(nearAntipodeMeters, 19_900_000.0)

    // 5. Non-finite & out-of-bounds inputs (never silently clamped to poles)
    let nanCoord = CLLocationCoordinate2D(latitude: .nan, longitude: -1.0)
    let infCoord = CLLocationCoordinate2D(latitude: 46.0, longitude: .infinity)
    let outOfBoundsLat = CLLocationCoordinate2D(latitude: 95.0, longitude: 0.0)
    let outOfBoundsLon = CLLocationCoordinate2D(latitude: 46.0, longitude: 181.0)

    XCTAssertNil(laRochelle.geodesicDistance(to: nanCoord))
    XCTAssertNil(laRochelle.geodesicDistance(to: infCoord))
    XCTAssertNil(laRochelle.geodesicDistance(to: outOfBoundsLat))
    XCTAssertNil(laRochelle.geodesicDistance(to: outOfBoundsLon))
    XCTAssertNil(kCLLocationCoordinate2DInvalid.geodesicDistance(to: laRochelle))

    XCTAssertTrue(laRochelle.distance(to: nanCoord).value.isNaN)
    XCTAssertTrue(laRochelle.distance(to: infCoord).value.isNaN)
    XCTAssertTrue(laRochelle.distance(to: outOfBoundsLat).value.isNaN)
    XCTAssertTrue(laRochelle.distance(to: outOfBoundsLon).value.isNaN)
    XCTAssertTrue(kCLLocationCoordinate2DInvalid.distance(to: laRochelle).value.isNaN)
  }

  // MARK: - Spherical Projections, Bearings & Cross-Track Error

  func testCircularPolygonGeneratesClosed65PointRingAndRejectsInvalidRadius() {
    let center = CLLocationCoordinate2D(latitude: 46.15, longitude: -1.15)

    XCTAssertNil(center.circularPolygon(radius: Measurement(value: 0.0, unit: .meters)))
    XCTAssertNil(center.circularPolygon(radius: Measurement(value: -10.0, unit: .meters)))
    XCTAssertNil(center.circularPolygon(radius: Measurement(value: .nan, unit: .meters)))

    let ring = center.circularPolygon(radius: Measurement(value: 50.0, unit: .meters))
    XCTAssertEqual(ring?.count, 65)
    XCTAssertEqual(ring?.first, ring?.last)
  }

  func testGreatCircleAndRhumbProjectionsAndAntiMeridianWrapping() throws {
    let start = CLLocationCoordinate2D(latitude: 45.0, longitude: 179.95)
    let eastBearing = Measurement(value: 90.0, unit: UnitAngle.degrees)
    let tenKm = Measurement(value: 10_000.0, unit: UnitLength.meters)

    let gcProjected = try XCTUnwrap(start.greatCircleCoordinate(atDistance: tenKm, bearing: eastBearing))
    let rhumbProjected = try XCTUnwrap(start.rhumbCoordinate(atDistance: tenKm, bearing: eastBearing))

    // Crossing 180° eastward wraps into negative West longitude [-180, 0)
    XCTAssertLessThan(gcProjected.longitude, 0.0)
    XCTAssertGreaterThanOrEqual(gcProjected.longitude, -180.0)
    XCTAssertLessThan(rhumbProjected.longitude, 0.0)

    // Constant 90° rhumb line strictly preserves latitude (loxodrome along a parallel)
    XCTAssertEqual(rhumbProjected.latitude, 45.0, accuracy: 1e-9)

    // Invalid inputs return nil
    XCTAssertNil(start.greatCircleCoordinate(atDistance: Measurement(value: -1.0, unit: .meters), bearing: eastBearing))
    XCTAssertNil(start.rhumbCoordinate(atDistance: tenKm, bearing: Measurement(value: .nan, unit: .degrees)))
  }

  func testGreatCircleBearingCardinalDirectionsAndIndeterminateSamePoint() throws {
    let origin = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)

    XCTAssertNil(origin.greatCircleBearing(to: origin))
    XCTAssertNil(origin.greatCircleBearing(to: CLLocationCoordinate2D(latitude: .nan, longitude: 0.0)))

    let north = try XCTUnwrap(origin.greatCircleBearing(to: CLLocationCoordinate2D(latitude: 10.0, longitude: 0.0)))
    let east = try XCTUnwrap(origin.greatCircleBearing(to: CLLocationCoordinate2D(latitude: 0.0, longitude: 10.0)))
    let south = try XCTUnwrap(origin.greatCircleBearing(to: CLLocationCoordinate2D(latitude: -10.0, longitude: 0.0)))
    let west = try XCTUnwrap(origin.greatCircleBearing(to: CLLocationCoordinate2D(latitude: 0.0, longitude: -10.0)))

    XCTAssertEqual(north.converted(to: .degrees).value, 0.0, accuracy: 1e-9)
    XCTAssertEqual(east.converted(to: .degrees).value, 90.0, accuracy: 1e-9)
    XCTAssertEqual(south.converted(to: .degrees).value, 180.0, accuracy: 1e-9)
    XCTAssertEqual(west.converted(to: .degrees).value, 270.0, accuracy: 1e-9)
  }

  func testCrossTrackErrorSignSymmetryAndSphericalConsistency() throws {
    // Leg along the equator from (0°, 0°) due East to (0°, 1°) -> track bearing = 90°
    let legOrigin = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
    let legDestination = CLLocationCoordinate2D(latitude: 0.0, longitude: 1.0)

    // Point directly on track -> 0 m XTE
    let onTrack = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.5)
    let zeroXTE = try XCTUnwrap(onTrack.crossTrackError(from: legOrigin, to: legDestination))
    XCTAssertEqual(zeroXTE.converted(to: .meters).value, 0.0, accuracy: 1e-6)

    // Point projected 1,000 m South (right/starboard of Eastbound leg) vs 1,000 m North (left/port)
    let offsetMeters = Measurement(value: 1_000.0, unit: UnitLength.meters)
    let starboardPoint = try XCTUnwrap(
      onTrack.greatCircleCoordinate(atDistance: offsetMeters, bearing: Measurement(value: 180.0, unit: .degrees))
    )
    let portPoint = try XCTUnwrap(
      onTrack.greatCircleCoordinate(atDistance: offsetMeters, bearing: Measurement(value: 0.0, unit: .degrees))
    )

    let starboardXTE = try XCTUnwrap(starboardPoint.crossTrackError(from: legOrigin, to: legDestination))
      .converted(to: .meters).value
    let portXTE = try XCTUnwrap(portPoint.crossTrackError(from: legOrigin, to: legDestination))
      .converted(to: .meters).value

    // Exact spherical self-consistency: projecting 1,000 m perpendicular to the equator yields exact ±1,000.000 m XTE
    XCTAssertEqual(starboardXTE, 1_000.0, accuracy: 0.01)
    XCTAssertEqual(portXTE, -1_000.0, accuracy: 0.01)

    // Indeterminate leg (origin == destination) returns nil
    XCTAssertNil(onTrack.crossTrackError(from: legOrigin, to: legOrigin))
  }
}
