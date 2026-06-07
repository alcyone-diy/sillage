//
//  WaypointTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
final class WaypointTests: XCTestCase {
  
  func testWaypointInitialization() {
    let coordinate = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let waypoint = Waypoint(name: "La Rochelle", coordinate: coordinate)
    
    // Check required fields
    XCTAssertEqual(waypoint.name, "La Rochelle")
    XCTAssertEqual(waypoint.coordinate.latitude, 46.16)
    XCTAssertEqual(waypoint.coordinate.longitude, -1.15)
    
    // Check defaults
    XCTAssertFalse(waypoint.id.isEmpty)
    XCTAssertTrue(waypoint.isVisible)
    XCTAssertNil(waypoint.description)
    XCTAssertNil(waypoint.symbol)
    XCTAssertNil(waypoint.colorHex)
    XCTAssertNotNil(waypoint.timestamp)
  }
  
  func testWaypointFullInitialization() {
    let coordinate = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let timestamp = Date(timeIntervalSince1970: 1000)
    let waypoint = Waypoint(
      id: "test-id",
      name: "La Rochelle",
      description: "Port des Minimes",
      symbol: "anchor",
      colorHex: "#FF0000",
      isVisible: false,
      coordinate: coordinate,
      timestamp: timestamp
    )
    
    XCTAssertEqual(waypoint.id, "test-id")
    XCTAssertEqual(waypoint.name, "La Rochelle")
    XCTAssertEqual(waypoint.description, "Port des Minimes")
    XCTAssertEqual(waypoint.symbol, "anchor")
    XCTAssertEqual(waypoint.colorHex, "#FF0000")
    XCTAssertFalse(waypoint.isVisible)
    XCTAssertEqual(waypoint.coordinate.latitude, 46.16)
    XCTAssertEqual(waypoint.coordinate.longitude, -1.15)
    XCTAssertEqual(waypoint.timestamp, timestamp)
  }
  
  func testWaypointEquality() {
    let coordinate = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let timestamp = Date(timeIntervalSince1970: 1000)
    
    let waypoint1 = Waypoint(
      id: "id-1",
      name: "Point A",
      coordinate: coordinate,
      timestamp: timestamp
    )
    
    let waypoint2 = Waypoint(
      id: "id-1",
      name: "Point A",
      coordinate: coordinate,
      timestamp: timestamp
    )
    
    let waypoint3 = Waypoint(
      id: "id-2", // Different ID
      name: "Point A",
      coordinate: coordinate,
      timestamp: timestamp
    )
    
    XCTAssertEqual(waypoint1, waypoint2)
    XCTAssertNotEqual(waypoint1, waypoint3)
  }
}
