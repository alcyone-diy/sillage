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
@testable import Sillage

@Suite("Geographic Bounding Box Tests")
struct GeographicBoundingBoxTests {

  @Test("Init with 4 coordinates")
  func testInitWithFourCoordinates() {
    let south = Measurement(value: 40.0, unit: UnitAngle.degrees)
    let north = Measurement(value: 50.0, unit: UnitAngle.degrees)
    let west = Measurement(value: -10.0, unit: UnitAngle.degrees)
    let east = Measurement(value: 10.0, unit: UnitAngle.degrees)
    
    let box = GeographicBoundingBox(southLatitude: south, northLatitude: north, westLongitude: west, eastLongitude: east)
    
    #expect(box.southLatitude == south)
    #expect(box.northLatitude == north)
    #expect(box.westLongitude == west)
    #expect(box.eastLongitude == east)
  }

  @Test("Init with single coordinate")
  func testInitWithSingleCoordinate() {
    let lat = Measurement(value: 45.0, unit: UnitAngle.degrees)
    let lon = Measurement(value: -5.0, unit: UnitAngle.degrees)
    
    let box = GeographicBoundingBox(latitude: lat, longitude: lon)
    
    #expect(box.southLatitude == lat)
    #expect(box.northLatitude == lat)
    #expect(box.westLongitude == lon)
    #expect(box.eastLongitude == lon)
  }
  
  @Test("Expand North")
  func testExpandNorth() {
    let initialLat = Measurement(value: 40.0, unit: UnitAngle.degrees)
    let initialLon = Measurement(value: -10.0, unit: UnitAngle.degrees)
    var box = GeographicBoundingBox(latitude: initialLat, longitude: initialLon)
    
    let newLat = Measurement(value: 50.0, unit: UnitAngle.degrees)
    box.expand(toIncludeLatitude: newLat, longitude: initialLon)
    
    #expect(box.southLatitude == initialLat)
    #expect(box.northLatitude == newLat)
    #expect(box.westLongitude == initialLon)
    #expect(box.eastLongitude == initialLon)
  }
  
  @Test("Expand South")
  func testExpandSouth() {
    let initialLat = Measurement(value: 40.0, unit: UnitAngle.degrees)
    let initialLon = Measurement(value: -10.0, unit: UnitAngle.degrees)
    var box = GeographicBoundingBox(latitude: initialLat, longitude: initialLon)
    
    let newLat = Measurement(value: 30.0, unit: UnitAngle.degrees)
    box.expand(toIncludeLatitude: newLat, longitude: initialLon)
    
    #expect(box.southLatitude == newLat)
    #expect(box.northLatitude == initialLat)
    #expect(box.westLongitude == initialLon)
    #expect(box.eastLongitude == initialLon)
  }
  
  @Test("Expand East")
  func testExpandEast() {
    let initialLat = Measurement(value: 40.0, unit: UnitAngle.degrees)
    let initialLon = Measurement(value: -10.0, unit: UnitAngle.degrees)
    var box = GeographicBoundingBox(latitude: initialLat, longitude: initialLon)
    
    let newLon = Measurement(value: 10.0, unit: UnitAngle.degrees)
    box.expand(toIncludeLatitude: initialLat, longitude: newLon)
    
    #expect(box.southLatitude == initialLat)
    #expect(box.northLatitude == initialLat)
    #expect(box.westLongitude == initialLon)
    #expect(box.eastLongitude == newLon)
  }
  
  @Test("Expand West")
  func testExpandWest() {
    let initialLat = Measurement(value: 40.0, unit: UnitAngle.degrees)
    let initialLon = Measurement(value: 10.0, unit: UnitAngle.degrees)
    var box = GeographicBoundingBox(latitude: initialLat, longitude: initialLon)
    
    let newLon = Measurement(value: -10.0, unit: UnitAngle.degrees)
    box.expand(toIncludeLatitude: initialLat, longitude: newLon)
    
    #expect(box.southLatitude == initialLat)
    #expect(box.northLatitude == initialLat)
    #expect(box.westLongitude == newLon)
    #expect(box.eastLongitude == initialLon)
  }

  @Test("Expand Inside Bounds")
  func testExpandInsideBounds() {
    let south = Measurement(value: 40.0, unit: UnitAngle.degrees)
    let north = Measurement(value: 50.0, unit: UnitAngle.degrees)
    let west = Measurement(value: -10.0, unit: UnitAngle.degrees)
    let east = Measurement(value: 10.0, unit: UnitAngle.degrees)
    
    var box = GeographicBoundingBox(southLatitude: south, northLatitude: north, westLongitude: west, eastLongitude: east)
    
    let insideLat = Measurement(value: 45.0, unit: UnitAngle.degrees)
    let insideLon = Measurement(value: 0.0, unit: UnitAngle.degrees)
    
    box.expand(toIncludeLatitude: insideLat, longitude: insideLon)
    
    #expect(box.southLatitude == south)
    #expect(box.northLatitude == north)
    #expect(box.westLongitude == west)
    #expect(box.eastLongitude == east)
  }
  
  @Test("Cross Antimeridian (Eastbound)")
  func testCrossAntimeridianEastbound() {
    let initialLat = Measurement(value: 40.0, unit: UnitAngle.degrees)
    let initialLon = Measurement(value: 175.0, unit: UnitAngle.degrees)
    var box = GeographicBoundingBox(latitude: initialLat, longitude: initialLon)
    
    let newLon = Measurement(value: -175.0, unit: UnitAngle.degrees)
    box.expand(toIncludeLatitude: initialLat, longitude: newLon)
    
    #expect(box.southLatitude == initialLat)
    #expect(box.northLatitude == initialLat)
    #expect(box.westLongitude == initialLon)
    #expect(box.eastLongitude == newLon)
  }
  
  @Test("Cross Antimeridian (Westbound)")
  func testCrossAntimeridianWestbound() {
    let initialLat = Measurement(value: 40.0, unit: UnitAngle.degrees)
    let initialLon = Measurement(value: -175.0, unit: UnitAngle.degrees)
    var box = GeographicBoundingBox(latitude: initialLat, longitude: initialLon)
    
    let newLon = Measurement(value: 175.0, unit: UnitAngle.degrees)
    box.expand(toIncludeLatitude: initialLat, longitude: newLon)
    
    #expect(box.southLatitude == initialLat)
    #expect(box.northLatitude == initialLat)
    #expect(box.westLongitude == newLon)
    #expect(box.eastLongitude == initialLon)
  }
  
  @Test("Inside Bounds over Antimeridian")
  func testInsideBoundsOverAntimeridian() {
    let south = Measurement(value: 40.0, unit: UnitAngle.degrees)
    let north = Measurement(value: 50.0, unit: UnitAngle.degrees)
    let west = Measurement(value: 170.0, unit: UnitAngle.degrees)
    let east = Measurement(value: -170.0, unit: UnitAngle.degrees)
    
    var box = GeographicBoundingBox(southLatitude: south, northLatitude: north, westLongitude: west, eastLongitude: east)
    
    // Test points that should be inside this box (e.g., 175, 180, -175)
    let insideLon1 = Measurement(value: 175.0, unit: UnitAngle.degrees)
    let insideLon2 = Measurement(value: -175.0, unit: UnitAngle.degrees)
    let insideLat = Measurement(value: 45.0, unit: UnitAngle.degrees)
    
    box.expand(toIncludeLatitude: insideLat, longitude: insideLon1)
    box.expand(toIncludeLatitude: insideLat, longitude: insideLon2)
    
    #expect(box.southLatitude == south)
    #expect(box.northLatitude == north)
    #expect(box.westLongitude == west)
    #expect(box.eastLongitude == east)
  }
}
