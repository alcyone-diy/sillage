//
//  CoordinateFormatStyleTests.swift
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

final class CoordinateFormatStyleTests: XCTestCase {

  private var northSymbol: String { String(localized: "N", comment: "North cardinal point") }
  private var southSymbol: String { String(localized: "S", comment: "South cardinal point") }
  private var eastSymbol: String { String(localized: "E", comment: "East cardinal point") }
  private var westSymbol: String { String(localized: "W", comment: "West cardinal point") }

  func testOriginZeroPaddingAndMarineCoordinateStaticStyle() {
    let origin = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
    let expected = "00° 00.000' \(northSymbol) / 000° 00.000' \(eastSymbol)"

    XCTAssertEqual(origin.formatted(), expected)
    XCTAssertEqual(CoordinateFormatStyle.marineCoordinate.format(origin), expected)
  }

  func testAllFourHemispheresAndArcminuteDecomposition() {
    // 46° 08.850' N = 46 + 8.85 / 60 = 46.1475
    // 001° 10.125' W = -(1 + 10.125 / 60) = -1.16875
    let nw = CLLocationCoordinate2D(latitude: 46.1475, longitude: -1.16875)
    XCTAssertEqual(
      nw.formatted(),
      "46° 08.850' \(northSymbol) / 001° 10.125' \(westSymbol)"
    )

    // 33° 51.540' S = -(33 + 51.54 / 60) = -33.859
    // 151° 12.600' E = 151 + 12.6 / 60 = 151.21
    let se = CLLocationCoordinate2D(latitude: -33.859, longitude: 151.21)
    XCTAssertEqual(
      se.formatted(),
      "33° 51.540' \(southSymbol) / 151° 12.600' \(eastSymbol)"
    )
  }

  func testRoundingNearSixtyMinutesCarriesIntoWholeDegree() {
    // 45° 59.9997' -> rounds to thousandths of a minute as 46° 00.000', never "45° 60.000'"
    let nearRolloverLat = 45.0 + (59.9997 / 60.0)
    let nearRolloverLon = -(9.0 + (59.9998 / 60.0))
    let coord = CLLocationCoordinate2D(latitude: nearRolloverLat, longitude: nearRolloverLon)

    XCTAssertEqual(
      coord.formatted(),
      "46° 00.000' \(northSymbol) / 010° 00.000' \(westSymbol)"
    )
    XCTAssertFalse(coord.formatted().contains("60.000'"))
  }

  func testBoundaryPolesAndAntiMeridianFormatCleanly() {
    let northAntiMeridian = CLLocationCoordinate2D(latitude: 90.0, longitude: 180.0)
    XCTAssertEqual(
      northAntiMeridian.formatted(),
      "90° 00.000' \(northSymbol) / 180° 00.000' \(eastSymbol)"
    )

    let southAntiMeridian = CLLocationCoordinate2D(latitude: -90.0, longitude: -180.0)
    XCTAssertEqual(
      southAntiMeridian.formatted(),
      "90° 00.000' \(southSymbol) / 180° 00.000' \(westSymbol)"
    )
  }

  func testInvalidAndNonFiniteCoordinatesReturnPlaceholder() {
    let placeholder = "--° --.---' / ---° --.---'"

    XCTAssertEqual(kCLLocationCoordinate2DInvalid.formatted(), placeholder)
    XCTAssertEqual(CLLocationCoordinate2D(latitude: 90.001, longitude: 0.0).formatted(), placeholder)
    XCTAssertEqual(CLLocationCoordinate2D(latitude: 0.0, longitude: -180.001).formatted(), placeholder)
    XCTAssertEqual(CLLocationCoordinate2D(latitude: .nan, longitude: -1.15).formatted(), placeholder)
    XCTAssertEqual(CLLocationCoordinate2D(latitude: 46.15, longitude: .infinity).formatted(), placeholder)
  }
}
