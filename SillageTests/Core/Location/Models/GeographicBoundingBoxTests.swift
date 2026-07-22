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
}
