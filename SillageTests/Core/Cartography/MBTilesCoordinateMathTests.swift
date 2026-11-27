//
//  MBTilesCoordinateMathTests.swift
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

final class MBTilesCoordinateMathTests: XCTestCase {

  func testTileCoordinateTMSInversionAndRoundTrip() {
    // Zoom 0: 1 tile (0, 0, 0) -> TMS row = 0
    let coordZ0 = TileCoordinate(zoom: 0, x: 0, y: 0)
    XCTAssertEqual(coordZ0.tmsRow, 0)
    XCTAssertEqual(MBTilesCoordinateMath.slippyY(tmsRow: 0, zoom: 0), 0)

    // Zoom 1: y=0 (North) -> TMS row = 1; y=1 (South) -> TMS row = 0
    let coordZ1North = TileCoordinate(zoom: 1, x: 0, y: 0)
    let coordZ1South = TileCoordinate(zoom: 1, x: 0, y: 1)
    XCTAssertEqual(coordZ1North.tmsRow, 1)
    XCTAssertEqual(coordZ1South.tmsRow, 0)

    // Zoom 3: max y = 7. Round-trip every row in 0...7
    for slippyY in 0...7 {
      let tms = MBTilesCoordinateMath.tmsRow(slippyY: slippyY, zoom: 3)
      XCTAssertEqual(tms, 7 - slippyY)
      if let tms {
        XCTAssertEqual(MBTilesCoordinateMath.slippyY(tmsRow: tms, zoom: 3), slippyY)
      }
    }
  }

  func testTileCoordinateComparableOrdering() {
    let unsorted: [TileCoordinate] = [
      TileCoordinate(zoom: 2, x: 1, y: 0),
      TileCoordinate(zoom: 1, x: 1, y: 1),
      TileCoordinate(zoom: 1, x: 0, y: 1),
      TileCoordinate(zoom: 1, x: 0, y: 0)
    ]

    XCTAssertEqual(
      unsorted.sorted(),
      [
        TileCoordinate(zoom: 1, x: 0, y: 0),
        TileCoordinate(zoom: 1, x: 0, y: 1),
        TileCoordinate(zoom: 1, x: 1, y: 1),
        TileCoordinate(zoom: 2, x: 1, y: 0)
      ]
    )
  }

  func testMercatorTileProjectionWithMeasurement() {
    // Equator / Prime Meridian (0, 0) at Zoom 1
    let x = MBTilesCoordinateMath.tileX(longitude: 0, zoom: 1)
    let y = MBTilesCoordinateMath.tileY(latitude: 0, zoom: 1)
    XCTAssertEqual(x, 1)
    XCTAssertEqual(y, 1)

    // La Rochelle (~46.15° N, ~1.15° W) at Zoom 10 -> known Slippy tile (508, 363)
    XCTAssertEqual(MBTilesCoordinateMath.tileX(longitude: -1.15, zoom: 10), 508)
    XCTAssertEqual(MBTilesCoordinateMath.tileY(latitude: 46.15, zoom: 10), 363)
  }

  func testNilOverDefaultsForInvalidInputs() {
    // Invalid zoom (< 0 or > 30)
    XCTAssertNil(MBTilesCoordinateMath.tileX(longitude: 0, zoom: -1))
    XCTAssertNil(MBTilesCoordinateMath.tileX(longitude: 0, zoom: 31))
    XCTAssertNil(MBTilesCoordinateMath.tileY(latitude: 0, zoom: -1))
    XCTAssertNil(MBTilesCoordinateMath.tileY(latitude: 0, zoom: 31))

    // Invalid coordinates (NaN, Infinite, out-of-bounds)
    XCTAssertNil(MBTilesCoordinateMath.tileX(longitude: .nan, zoom: 5))
    XCTAssertNil(MBTilesCoordinateMath.tileX(longitude: 195.0, zoom: 5))
    XCTAssertNil(MBTilesCoordinateMath.tileX(longitude: -180.1, zoom: 5))
    XCTAssertNil(MBTilesCoordinateMath.tileY(latitude: .infinity, zoom: 5))
    XCTAssertNil(MBTilesCoordinateMath.tileY(latitude: 89.0, zoom: 5)) // Beyond Mercator limit ~85.0511°
    XCTAssertNil(MBTilesCoordinateMath.tileY(latitude: -86.0, zoom: 5))

    // Invalid TMS row / Slippy Y (out-of-bounds index)
    XCTAssertNil(MBTilesCoordinateMath.tmsRow(slippyY: 10, zoom: 1))
    XCTAssertNil(MBTilesCoordinateMath.tmsRow(slippyY: -1, zoom: 1))
    XCTAssertNil(MBTilesCoordinateMath.slippyY(tmsRow: -1, zoom: 1))
    XCTAssertNil(MBTilesCoordinateMath.slippyY(tmsRow: 2, zoom: 1))
    XCTAssertNil(MBTilesCoordinateMath.slippyY(tmsRow: 0, zoom: -1))

    let invalidCoord = TileCoordinate(zoom: 1, x: 0, y: 99)
    XCTAssertNil(invalidCoord.tmsRow)
  }

  func testTileXAt180NormalizesToZeroAndAntiMeridianBoundsIncludeWestSegment() {
    // Point semantics: +180.0° and -180.0° share the same meridian (column 0)
    XCTAssertEqual(MBTilesCoordinateMath.tileX(longitude: 180.0, zoom: 2), 0)
    XCTAssertEqual(MBTilesCoordinateMath.tileX(longitude: -180.0, zoom: 2), 0)

    // Bounding box crossing the anti-meridian (170°E to 170°W) at zoom 2 (4x4 grid, columns 0..3)
    // West segment [170, 180] -> column 3; East segment [-180, -170] -> column 0
    let antiMeridianBounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: -10.0, longitude: 170.0),
      northEast: CLLocationCoordinate2D(latitude: 10.0, longitude: -170.0)
    )
    let tiles = MBTilesCoordinateMath.tileCoordinates(for: antiMeridianBounds, zoom: 2)
    let xColumns = Set(tiles.map(\.x))

    XCTAssertTrue(xColumns.contains(3), "West segment ending at 180.0° must include rightmost column (1 << zoom) - 1")
    XCTAssertTrue(xColumns.contains(0), "East segment starting at -180.0° must include column 0")
    XCTAssertEqual(xColumns, [0, 3])
    XCTAssertEqual(MBTilesCoordinateMath.tileCount(for: antiMeridianBounds, zoom: 2), tiles.count)
  }

  func testTileCountClampLatitudeBehaviorNearPoles() {
    let polarBounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: -89.0, longitude: -10.0),
      northEast: CLLocationCoordinate2D(latitude: 89.0, longitude: 10.0)
    )

    // Unclamped exceeds Web Mercator limit (~85.0511°), yielding 0 valid tiles
    XCTAssertEqual(MBTilesCoordinateMath.tileCount(for: polarBounds, zoom: 1, clampLatitude: false), 0)

    // Clamped restricts latitudes to [-85.0511°, +85.0511°], covering both columns and both rows at zoom 1 (2x2 = 4)
    XCTAssertEqual(MBTilesCoordinateMath.tileCount(for: polarBounds, zoom: 1, clampLatitude: true), 4)
  }

  func testAllTileCoordinatesAcrossZoomRangeAndInvalidRanges() {
    let harborBounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 46.14, longitude: -1.18),
      northEast: CLLocationCoordinate2D(latitude: 46.16, longitude: -1.16)
    )

    // Single-point-like small box occupies 1 tile at z=0, z=1, z=2 -> 3 tiles total
    let multiZoomTiles = MBTilesCoordinateMath.allTileCoordinates(for: harborBounds, minZoom: 0, maxZoom: 2)
    XCTAssertEqual(multiZoomTiles.map(\.zoom), [0, 1, 2])

    // Invalid zoom bounds return empty collection
    XCTAssertTrue(MBTilesCoordinateMath.allTileCoordinates(for: harborBounds, minZoom: 5, maxZoom: 3).isEmpty)
    XCTAssertTrue(MBTilesCoordinateMath.allTileCoordinates(for: harborBounds, minZoom: -1, maxZoom: 2).isEmpty)
    XCTAssertTrue(MBTilesCoordinateMath.allTileCoordinates(for: harborBounds, minZoom: 0, maxZoom: 31).isEmpty)
  }
}
