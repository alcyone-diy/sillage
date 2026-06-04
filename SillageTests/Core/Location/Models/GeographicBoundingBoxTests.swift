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
}
