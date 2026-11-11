//
//  AstronomicalServiceTests.swift
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

final class AstronomicalServiceTests: XCTestCase {

  private var service: AstronomicalService!

  override func setUp() async throws {
    try await super.setUp()
    service = AstronomicalService()
  }

  override func tearDown() async throws {
    service = nil
    try await super.tearDown()
  }

  func testValidCoordinateCalculatesEphemeris() async {
    // La Rochelle: 46.1603° N, 1.1511° W
    let laRochelle = CLLocationCoordinate2D(latitude: 46.1603, longitude: -1.1511)
    
    // A fixed summer date (2026-06-21 at 12:00:00 UTC)
    var components = DateComponents()
    components.year = 2026
    components.month = 6
    components.day = 21
    components.hour = 12
    components.timeZone = TimeZone(identifier: "UTC")
    let calendar = Calendar(identifier: .gregorian)
    guard let date = calendar.date(from: components) else {
      XCTFail("Failed to construct test date")
      return
    }

    let ephemeris = await service.calculateEphemeris(for: laRochelle, date: date)
    XCTAssertNotNil(ephemeris)

    guard let ephemeris else { return }
    XCTAssertNotNil(ephemeris.sunrise)
    XCTAssertNotNil(ephemeris.sunset)
    XCTAssertNotNil(ephemeris.nauticalTwilightStart)
    XCTAssertNotNil(ephemeris.nauticalTwilightEnd)

    if let dawn = ephemeris.nauticalTwilightStart,
       let rise = ephemeris.sunrise,
       let set = ephemeris.sunset,
       let dusk = ephemeris.nauticalTwilightEnd {
      // Dawn (nautical twilight start) happens before sunrise
      XCTAssertLessThan(dawn, rise)
      // Sunrise happens before sunset
      XCTAssertLessThan(rise, set)
      // Sunset happens before dusk (nautical twilight end)
      XCTAssertLessThan(set, dusk)
    }
  }

  func testInvalidCoordinateReturnsNil() async {
    let invalidCoord1 = CLLocationCoordinate2D(latitude: 100.0, longitude: 0.0)
    let ephemeris1 = await service.calculateEphemeris(for: invalidCoord1, date: Date())
    XCTAssertNil(ephemeris1)

    let invalidCoord2 = CLLocationCoordinate2D(latitude: -95.0, longitude: 200.0)
    let ephemeris2 = await service.calculateEphemeris(for: invalidCoord2, date: Date())
    XCTAssertNil(ephemeris2)
  }

  func testConvenienceMethodMatches() async {
    let coordinate = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
    let date = Date()

    let ephemeris1 = await service.calculateEphemeris(for: coordinate, date: date)
    let ephemeris2 = await service.ephemeris(for: coordinate, date: date)

    XCTAssertEqual(ephemeris1, ephemeris2)
  }

  func testSunEphemerisSendableAcrossTasks() async {
    let coordinate = CLLocationCoordinate2D(latitude: 43.2965, longitude: 5.3698) // Marseille
    let ephemeris = await service.calculateEphemeris(for: coordinate, date: Date())

    let sendableCopy = await Task.detached { () -> SunEphemeris? in
      return ephemeris
    }.value

    XCTAssertEqual(ephemeris, sendableCopy)
  }
}
