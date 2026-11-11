//
//  MagneticDeclinationServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

final class MagneticDeclinationServiceTests: XCTestCase {

  private var service: MagneticDeclinationService!

  override func setUp() async throws {
    try await super.setUp()
    service = MagneticDeclinationService()
  }

  override func tearDown() async throws {
    service = nil
    try await super.tearDown()
  }

  func testValidCoordinateReturnsDeclinationMeasurement() async {
    let coordinate = CLLocationCoordinate2D(latitude: 46.1603, longitude: -1.1511) // La Rochelle
    let declination = await service.calculateDeclination(for: coordinate, date: Date())

    XCTAssertNotNil(declination)
    XCTAssertEqual(declination?.unit, UnitAngle.degrees)
    XCTAssertEqual(declination?.value, -1.5)
  }

  func testInvalidCoordinateReturnsNilAndNeverZero() async {
    let invalidCoord1 = CLLocationCoordinate2D(latitude: 95.0, longitude: 0.0)
    let declination1 = await service.calculateDeclination(for: invalidCoord1, date: Date())
    XCTAssertNil(declination1, "Invalid latitude should return nil, never 0.0")

    let invalidCoord2 = CLLocationCoordinate2D(latitude: -91.0, longitude: 0.0)
    let declination2 = await service.calculateDeclination(for: invalidCoord2, date: Date())
    XCTAssertNil(declination2, "Invalid latitude should return nil, never 0.0")

    let invalidCoord3 = CLLocationCoordinate2D(latitude: 0.0, longitude: 185.0)
    let declination3 = await service.calculateDeclination(for: invalidCoord3, date: Date())
    XCTAssertNil(declination3, "Invalid longitude should return nil, never 0.0")
  }

  func testConvenienceMethodMatches() async {
    let coordinate = CLLocationCoordinate2D(latitude: 43.2965, longitude: 5.3698) // Marseille
    let date = Date()

    let declination1 = await service.calculateDeclination(for: coordinate, date: date)
    let declination2 = await service.declination(for: coordinate, date: date)

    XCTAssertEqual(declination1, declination2)
  }
}
