//
//  AnchorWatchTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

final class AnchorWatchTests: XCTestCase {
  
  func testAnchorWatchSerialization_withValidData() throws {
    let coordinate = CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0)
    let radius = Measurement(value: 50.0, unit: UnitLength.meters)
    let date = Date(timeIntervalSince1970: 1600000000)
    
    let model = AnchorWatch(coordinate: coordinate, radius: radius, createdAt: date)
    
    let encoder = JSONEncoder()
    let data = try encoder.encode(model)
    
    let decoder = JSONDecoder()
    let decodedModel = try decoder.decode(AnchorWatch.self, from: data)
    
    XCTAssertEqual(decodedModel.coordinate.latitude, 45.0)
    XCTAssertEqual(decodedModel.coordinate.longitude, -1.0)
    XCTAssertEqual(decodedModel.radius.value, 50.0)
    XCTAssertEqual(decodedModel.radius.unit, .meters)
    XCTAssertEqual(decodedModel.createdAt, date)
    XCTAssertEqual(decodedModel, model)
  }
  
  func testAnchorStatusSerialization() throws {
    let statuses: [AnchorStatus] = [.inactive, .armed, .dragging]
    
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    
    for status in statuses {
        let data = try encoder.encode(status)
        let decodedStatus = try decoder.decode(AnchorStatus.self, from: data)
        XCTAssertEqual(decodedStatus, status)
    }
  }
}
