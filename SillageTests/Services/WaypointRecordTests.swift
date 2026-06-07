//
//  WaypointRecordTests.swift
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
final class WaypointRecordTests: XCTestCase {
  
  func testDomainMapping() {
    let coordinate = CLLocationCoordinate2D(latitude: 46.16, longitude: -1.15)
    let timestamp = Date(timeIntervalSince1970: 1000.2)
    
    let domainWaypoint = Waypoint(
      id: "test-id",
      name: "La Rochelle",
      description: "Port des Minimes",
      symbol: "anchor",
      colorHex: "#FF0000",
      isVisible: true,
      coordinate: coordinate,
      timestamp: timestamp
    )
    
    // Convert to Record
    let record = WaypointRecord(domainModel: domainWaypoint)
    
    XCTAssertEqual(record.id, "test-id")
    XCTAssertEqual(record.name, "La Rochelle")
    XCTAssertEqual(record.description, "Port des Minimes")
    XCTAssertEqual(record.symbol, "anchor")
    XCTAssertEqual(record.color_hex, "#FF0000")
    XCTAssertTrue(record.isVisible)
    XCTAssertEqual(record.latitude_deg, 46.16)
    XCTAssertEqual(record.longitude_deg, -1.15)
    XCTAssertEqual(record.timestamp_unix, 1000.2, accuracy: 1e-7)
    
    // Convert back to Domain
    let mappedBack = record.toDomain()
    
    XCTAssertEqual(mappedBack.id, domainWaypoint.id)
    XCTAssertEqual(mappedBack.name, domainWaypoint.name)
    XCTAssertEqual(mappedBack.description, domainWaypoint.description)
    XCTAssertEqual(mappedBack.symbol, domainWaypoint.symbol)
    XCTAssertEqual(mappedBack.colorHex, domainWaypoint.colorHex)
    XCTAssertEqual(mappedBack.isVisible, domainWaypoint.isVisible)
    XCTAssertEqual(mappedBack.coordinate.latitude, domainWaypoint.coordinate.latitude)
    XCTAssertEqual(mappedBack.coordinate.longitude, domainWaypoint.coordinate.longitude)
    XCTAssertEqual(mappedBack.timestamp.timeIntervalSince1970, domainWaypoint.timestamp.timeIntervalSince1970)
  }
}
