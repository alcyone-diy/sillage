//
//  GeographicBoundingBoxTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
import CoreLocation
@testable import Sillage

@Suite("Geographic Bounding Box Tests")
struct GeographicBoundingBoxTests {

  @Test("Init with 4 coordinates")
  func testInitWithFourCoordinates() {
    let southWest = CLLocationCoordinate2D(latitude: 40.0, longitude: -10.0)
    let northEast = CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0)
    
    let box = GeographicBoundingBox(southWest: southWest, northEast: northEast)
    
    #expect(box.southWest.latitude == southWest.latitude)
    #expect(box.northEast.latitude == northEast.latitude)
    #expect(box.southWest.longitude == southWest.longitude)
    #expect(box.northEast.longitude == northEast.longitude)
  }

  @Test("Init with single coordinate")
  func testInitWithSingleCoordinate() {
    let coordinate = CLLocationCoordinate2D(latitude: 45.0, longitude: -5.0)
    
    let box = GeographicBoundingBox(coordinate: coordinate)
    
    #expect(box.southWest.latitude == coordinate.latitude)
    #expect(box.northEast.latitude == coordinate.latitude)
    #expect(box.southWest.longitude == coordinate.longitude)
    #expect(box.northEast.longitude == coordinate.longitude)
  }
  
  @Test("Expand North")
  func testExpandNorth() {
    let initialCoordinate = CLLocationCoordinate2D(latitude: 40.0, longitude: -10.0)
    var box = GeographicBoundingBox(coordinate: initialCoordinate)
    
    let newCoordinate = CLLocationCoordinate2D(latitude: 50.0, longitude: -10.0)
    box.expand(toInclude: newCoordinate)
    
    #expect(box.southWest.latitude == initialCoordinate.latitude)
    #expect(box.northEast.latitude == newCoordinate.latitude)
    #expect(box.southWest.longitude == initialCoordinate.longitude)
    #expect(box.northEast.longitude == initialCoordinate.longitude)
  }
  
  @Test("Expand South")
  func testExpandSouth() {
    let initialCoordinate = CLLocationCoordinate2D(latitude: 40.0, longitude: -10.0)
    var box = GeographicBoundingBox(coordinate: initialCoordinate)
    
    let newCoordinate = CLLocationCoordinate2D(latitude: 30.0, longitude: -10.0)
    box.expand(toInclude: newCoordinate)
    
    #expect(box.southWest.latitude == newCoordinate.latitude)
    #expect(box.northEast.latitude == initialCoordinate.latitude)
    #expect(box.southWest.longitude == initialCoordinate.longitude)
    #expect(box.northEast.longitude == initialCoordinate.longitude)
  }
  
  @Test("Expand East")
  func testExpandEast() {
    let initialCoordinate = CLLocationCoordinate2D(latitude: 40.0, longitude: -10.0)
    var box = GeographicBoundingBox(coordinate: initialCoordinate)
    
    let newCoordinate = CLLocationCoordinate2D(latitude: 40.0, longitude: 10.0)
    box.expand(toInclude: newCoordinate)
    
    #expect(box.southWest.latitude == initialCoordinate.latitude)
    #expect(box.northEast.latitude == initialCoordinate.latitude)
    #expect(box.southWest.longitude == initialCoordinate.longitude)
    #expect(box.northEast.longitude == newCoordinate.longitude)
  }
  
  @Test("Expand West")
  func testExpandWest() {
    let initialCoordinate = CLLocationCoordinate2D(latitude: 40.0, longitude: 10.0)
    var box = GeographicBoundingBox(coordinate: initialCoordinate)
    
    let newCoordinate = CLLocationCoordinate2D(latitude: 40.0, longitude: -10.0)
    box.expand(toInclude: newCoordinate)
    
    #expect(box.southWest.latitude == initialCoordinate.latitude)
    #expect(box.northEast.latitude == initialCoordinate.latitude)
    #expect(box.southWest.longitude == newCoordinate.longitude)
    #expect(box.northEast.longitude == initialCoordinate.longitude)
  }

  @Test("Expand Inside Bounds")
  func testExpandInsideBounds() {
    let southWest = CLLocationCoordinate2D(latitude: 40.0, longitude: -10.0)
    let northEast = CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0)
    
    var box = GeographicBoundingBox(southWest: southWest, northEast: northEast)
    
    let insideCoordinate = CLLocationCoordinate2D(latitude: 45.0, longitude: 0.0)
    
    box.expand(toInclude: insideCoordinate)
    
    #expect(box.southWest.latitude == southWest.latitude)
    #expect(box.northEast.latitude == northEast.latitude)
    #expect(box.southWest.longitude == southWest.longitude)
    #expect(box.northEast.longitude == northEast.longitude)
  }
  
  @Test("Cross Antimeridian (Eastbound)")
  func testCrossAntimeridianEastbound() {
    let initialCoordinate = CLLocationCoordinate2D(latitude: 40.0, longitude: 175.0)
    var box = GeographicBoundingBox(coordinate: initialCoordinate)
    
    let newCoordinate = CLLocationCoordinate2D(latitude: 40.0, longitude: -175.0)
    box.expand(toInclude: newCoordinate)
    
    #expect(box.southWest.latitude == initialCoordinate.latitude)
    #expect(box.northEast.latitude == initialCoordinate.latitude)
    #expect(box.southWest.longitude == initialCoordinate.longitude)
    #expect(box.northEast.longitude == newCoordinate.longitude)
  }
  
  @Test("Cross Antimeridian (Westbound)")
  func testCrossAntimeridianWestbound() {
    let initialCoordinate = CLLocationCoordinate2D(latitude: 40.0, longitude: -175.0)
    var box = GeographicBoundingBox(coordinate: initialCoordinate)
    
    let newCoordinate = CLLocationCoordinate2D(latitude: 40.0, longitude: 175.0)
    box.expand(toInclude: newCoordinate)
    
    #expect(box.southWest.latitude == initialCoordinate.latitude)
    #expect(box.northEast.latitude == initialCoordinate.latitude)
    #expect(box.southWest.longitude == newCoordinate.longitude)
    #expect(box.northEast.longitude == initialCoordinate.longitude)
  }
  
  @Test("Inside Bounds over Antimeridian")
  func testInsideBoundsOverAntimeridian() {
    let southWest = CLLocationCoordinate2D(latitude: 40.0, longitude: 170.0)
    let northEast = CLLocationCoordinate2D(latitude: 50.0, longitude: -170.0)
    
    var box = GeographicBoundingBox(southWest: southWest, northEast: northEast)
    
    // Test points that should be inside this box (e.g., 175, 180, -175)
    let insideCoordinate1 = CLLocationCoordinate2D(latitude: 45.0, longitude: 175.0)
    let insideCoordinate2 = CLLocationCoordinate2D(latitude: 45.0, longitude: -175.0)
    
    box.expand(toInclude: insideCoordinate1)
    box.expand(toInclude: insideCoordinate2)
    
    #expect(box.southWest.latitude == southWest.latitude)
    #expect(box.northEast.latitude == northEast.latitude)
    #expect(box.southWest.longitude == southWest.longitude)
    #expect(box.northEast.longitude == northEast.longitude)
  }
  
  // MARK: - Equivalence Tests (Epsilon)
  
  @Test("isApproximatelyEqual: Exact equality returns true")
  func testIsApproximatelyEqualExact() {
    let box1 = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 40.0, longitude: -10.0),
      northEast: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0)
    )
    let box2 = box1
    
    #expect(box1.isApproximatelyEqual(to: box2))
  }
  
  @Test("isApproximatelyEqual: Slight variations below 1e-6 return true")
  func testIsApproximatelyEqualBelowTolerance() {
    let box1 = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 40.0, longitude: -10.0),
      northEast: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0)
    )
    // Variation of 0.0000005 (5e-7), which is less than default 1e-6 tolerance
    let box2 = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 40.0 + 5e-7, longitude: -10.0 - 5e-7),
      northEast: CLLocationCoordinate2D(latitude: 50.0 - 5e-7, longitude: 10.0 + 5e-7)
    )
    
    #expect(box1.isApproximatelyEqual(to: box2))
  }
  
  @Test("isApproximatelyEqual: Variations above 1e-6 return false")
  func testIsApproximatelyEqualAboveTolerance() {
    let box1 = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 40.0, longitude: -10.0),
      northEast: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0)
    )
    // Variation of 0.000002 (2e-6), which is strictly greater than default 1e-6 tolerance
    let box2 = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 40.0 + 2e-6, longitude: -10.0),
      northEast: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0)
    )
    
    #expect(!box1.isApproximatelyEqual(to: box2))
  }
  
  @Test("isApproximatelyEqual: Edge cases near anti-meridian and poles")
  func testIsApproximatelyEqualEdgeCases() {
    // Near poles (same coordinate, no wrap, just exact equivalence near pole)
    let polesBox1 = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: -89.9999999, longitude: 0.0),
      northEast: CLLocationCoordinate2D(latitude: 89.9999999, longitude: 0.0)
    )
    let polesBox2 = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: -90.0, longitude: 0.0),
      northEast: CLLocationCoordinate2D(latitude: 90.0, longitude: 0.0)
    )
    #expect(polesBox1.isApproximatelyEqual(to: polesBox2))
    
    // Near anti-meridian (Wrap around 180 / -180)
    // 179.999999 and -179.999999 are ~0.000002 degrees apart across the anti-meridian
    let amBox1 = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 0.0, longitude: 179.999999),
      northEast: CLLocationCoordinate2D(latitude: 0.0, longitude: -179.999999)
    )
    let amBox2 = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 0.0, longitude: -179.999999),
      northEast: CLLocationCoordinate2D(latitude: 0.0, longitude: 179.999999)
    )
    
    // An absolute delta would yield ~360, but shortest path is ~0.000002.
    // 0.000002 is smaller than the provided tolerance of 1e-5 (0.00001).
    #expect(amBox1.isApproximatelyEqual(to: amBox2, tolerance: 1e-5))
  }

  // MARK: - WKT & Polygon Tests

  @Test("WKT roundtrip serialization and parsing")
  func testWKTRoundtrip() {
    let original = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 46.12345, longitude: -1.56789),
      northEast: CLLocationCoordinate2D(latitude: 46.98765, longitude: -1.12345)
    )
    let wkt = original.toWKT()
    let parsed = GeographicBoundingBox.fromWKT(wkt)

    #expect(parsed != nil)
    if let parsed {
      #expect(parsed.isApproximatelyEqual(to: original, tolerance: 1e-5))
      #expect(parsed.southWest.latitude == original.southWest.latitude)
      #expect(parsed.southWest.longitude == original.southWest.longitude)
      #expect(parsed.northEast.latitude == original.northEast.latitude)
      #expect(parsed.northEast.longitude == original.northEast.longitude)
    }
  }

  @Test("WKT parsing with init(wkt:)")
  func testWKTFailableInit() {
    let validWKT = "POLYGON((-1.5 46.1, -1.1 46.1, -1.1 46.3, -1.5 46.3, -1.5 46.1))"
    let box = GeographicBoundingBox(wkt: validWKT)
    #expect(box != nil)
    #expect(box?.southWest.latitude == 46.1)
    #expect(box?.southWest.longitude == -1.5)
    #expect(box?.northEast.latitude == 46.3)
    #expect(box?.northEast.longitude == -1.1)

    let invalidWKT = "POINT(10 20)"
    let invalidBox = GeographicBoundingBox(wkt: invalidWKT)
    #expect(invalidBox == nil)
  }

  @Test("WKT parsing with irregular formatting and whitespace")
  func testWKTIrregularFormatting() {
    let wkt = "  polygon ( ( -1.500000   46.100000 ,  -1.100000   46.100000 , -1.100000  46.300000 , -1.500000  46.300000 , -1.500000  46.100000 ) ) "
    let box = GeographicBoundingBox.fromWKT(wkt)
    #expect(box != nil)
    #expect(box?.southWest.latitude == 46.1)
    #expect(box?.southWest.longitude == -1.5)
  }

  @Test("WKT parsing returns nil on out-of-range coordinates")
  func testWKTOutOfRange() {
    let invalidLat = "POLYGON((-1.5 95.0, -1.1 95.0, -1.1 96.0, -1.5 96.0, -1.5 95.0))"
    #expect(GeographicBoundingBox.fromWKT(invalidLat) == nil)

    let invalidLon = "POLYGON((-195.0 45.0, -190.0 45.0, -190.0 46.0, -195.0 46.0, -195.0 45.0))"
    #expect(GeographicBoundingBox.fromWKT(invalidLon) == nil)
  }

  @Test("polygonCoordinates returns 5 closed vertices in counter-clockwise/rectangular order")
  func testPolygonCoordinates() {
    let box = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 40.0, longitude: -10.0),
      northEast: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0)
    )
    let coords = box.polygonCoordinates

    #expect(coords.count == 5)
    // SW
    #expect(coords[0].latitude == 40.0 && coords[0].longitude == -10.0)
    // SE
    #expect(coords[1].latitude == 40.0 && coords[1].longitude == 10.0)
    // NE
    #expect(coords[2].latitude == 50.0 && coords[2].longitude == 10.0)
    // NW
    #expect(coords[3].latitude == 50.0 && coords[3].longitude == -10.0)
    // SW (closed)
    #expect(coords[4].latitude == 40.0 && coords[4].longitude == -10.0)
  }

  @Test("splitAtAntiMeridian splits crossing box into two valid segments")
  func testSplitAtAntiMeridian() {
    let normalBox = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 10.0, longitude: 20.0),
      northEast: CLLocationCoordinate2D(latitude: 30.0, longitude: 40.0)
    )
    #expect(!normalBox.crossesAntiMeridian)
    #expect(normalBox.splitAtAntiMeridian().count == 1)

    let crossingBox = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 10.0, longitude: 170.0),
      northEast: CLLocationCoordinate2D(latitude: 30.0, longitude: -160.0)
    )
    #expect(crossingBox.crossesAntiMeridian)
    let segments = crossingBox.splitAtAntiMeridian()
    #expect(segments.count == 2)
    #expect(segments[0].southWest.longitude == 170.0)
    #expect(segments[0].northEast.longitude == 180.0)
    #expect(segments[1].southWest.longitude == -180.0)
    #expect(segments[1].northEast.longitude == -160.0)
  }

  @Test("WKT parsing preserves anti-meridian crossing direction natively")
  func testWKTAntiMeridianPreserved() {
    let wkt = "POLYGON((170.0 40.0, -170.0 40.0, -170.0 50.0, 170.0 50.0, 170.0 40.0))"
    let box = GeographicBoundingBox.fromWKT(wkt)

    #expect(box != nil)
    if let box {
      #expect(box.crossesAntiMeridian)
      #expect(box.southWest.latitude == 40.0)
      #expect(box.southWest.longitude == 170.0)
      #expect(box.northEast.latitude == 50.0)
      #expect(box.northEast.longitude == -170.0)

      let split = box.splitAtAntiMeridian()
      #expect(split.count == 2)
      #expect(split[0].southWest.longitude == 170.0)
      #expect(split[0].northEast.longitude == 180.0)
      #expect(split[1].southWest.longitude == -180.0)
      #expect(split[1].northEast.longitude == -170.0)
    }
  }

  // MARK: - Intersection & Non-Intersecting Polygon Union Tests

  @Test("intersects correctly detects overlapping and non-overlapping boxes")
  func testIntersects() {
    let box1 = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 40.0, longitude: 0.0),
      northEast: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0)
    )
    let boxOverlapping = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0),
      northEast: CLLocationCoordinate2D(latitude: 55.0, longitude: 15.0)
    )
    let boxDisjoint = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 60.0, longitude: 20.0),
      northEast: CLLocationCoordinate2D(latitude: 70.0, longitude: 30.0)
    )

    #expect(box1.intersects(boxOverlapping))
    #expect(boxOverlapping.intersects(box1))
    #expect(!box1.intersects(boxDisjoint))
    #expect(!boxDisjoint.intersects(box1))
  }

  @Test("mergeIntoNonIntersectingPolygons merges overlapping boxes into an exact orthogonal L-shaped polygon without over-masking")
  func testMergeIntoNonIntersectingPolygonsLShaped() {
    // Box A: Lat 0..10, Lon 0..10
    let boxA = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
      northEast: CLLocationCoordinate2D(latitude: 10.0, longitude: 10.0)
    )
    // Box B: Lat 5..15, Lon 5..15 (overlaps with Box A)
    let boxB = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 5.0, longitude: 5.0),
      northEast: CLLocationCoordinate2D(latitude: 15.0, longitude: 15.0)
    )

    let polygons = GeographicBoundingBox.mergeIntoNonIntersectingPolygons([boxA, boxB])

    // Should merge into exactly 1 closed polygon
    #expect(polygons.count == 1)

    if let contour = polygons.first {
      // An orthogonal union of 2 overlapping squares has 8 distinct corners (+ 1 closed vertex = 9 coordinates)
      #expect(contour.count >= 8)
      // First and last coordinates must match (closed ring)
      #expect(contour.first?.latitude == contour.last?.latitude)
      #expect(contour.first?.longitude == contour.last?.longitude)

      // Ensure the corners of the L-shape exist
      let containsOrigin = contour.contains { $0.latitude == 0.0 && $0.longitude == 0.0 }
      let containsTopRight = contour.contains { $0.latitude == 15.0 && $0.longitude == 15.0 }
      #expect(containsOrigin)
      #expect(containsTopRight)

      // Crucial Safety Check: Verify that the non-downloaded corners (0, 15) and (15, 0) are NOT vertices
      let falselyContainsTopLeft = contour.contains { $0.latitude == 15.0 && $0.longitude == 0.0 }
      let falselyContainsBottomRight = contour.contains { $0.latitude == 0.0 && $0.longitude == 15.0 }
      #expect(!falselyContainsTopLeft)
      #expect(!falselyContainsBottomRight)
    }
  }

  @Test("mergeIntoNonIntersectingPolygons keeps disjoint boxes as separate polygon rings")
  func testMergeIntoNonIntersectingPolygonsDisjoint() {
    let boxA = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
      northEast: CLLocationCoordinate2D(latitude: 10.0, longitude: 10.0)
    )
    let boxB = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 40.0, longitude: 40.0),
      northEast: CLLocationCoordinate2D(latitude: 50.0, longitude: 50.0)
    )

    let polygons = GeographicBoundingBox.mergeIntoNonIntersectingPolygons([boxA, boxB])

    #expect(polygons.count == 2)
    #expect(polygons[0].count == 5) // 4 corners + 1 closed
    #expect(polygons[1].count == 5)
  }
}

