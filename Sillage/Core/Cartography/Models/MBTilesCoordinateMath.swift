//
//  MBTilesCoordinateMath.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Coordinate descriptor representing a single Slippy Map XYZ tile position.
nonisolated public struct TileCoordinate: Hashable, Sendable, Comparable {
  public let zoom: Int
  public let x: Int
  public let y: Int

  public init(zoom: Int, x: Int, y: Int) {
    self.zoom = zoom
    self.x = x
    self.y = y
  }

  /// Calculates the inverted TMS row index matching the MBTiles 1.3 specification.
  ///
  /// In the Slippy Map convention, `y = 0` is at the North Pole.
  /// In the TMS / MBTiles convention, `tile_row = 0` is at the South Pole.
  /// Returns `nil` if the zoom or tile row is outside valid Web Mercator limits.
  public var tmsRow: Int? {
    MBTilesCoordinateMath.tmsRow(slippyY: y, zoom: zoom)
  }

  public static func < (lhs: TileCoordinate, rhs: TileCoordinate) -> Bool {
    if lhs.zoom != rhs.zoom { return lhs.zoom < rhs.zoom }
    if lhs.x != rhs.x { return lhs.x < rhs.x }
    return lhs.y < rhs.y
  }
}

/// Mathematical projection utilities converting WGS84 geographic coordinates
/// to Web Mercator Slippy Map / MBTiles TMS tile indices using `Foundation.Measurement`.
nonisolated public enum MBTilesCoordinateMath {

  /// Web Mercator maximum projected latitude limit (~85.05112878 degrees).
  private static let maxMercatorLatitudeDegrees: Double = 85.0511287798066

  /// Converts a WGS84 longitude into a Slippy Map tile X coordinate at the specified zoom.
  /// Returns `nil` if inputs are invalid or outside valid bounds (Nil over Defaults).
  public static func tileX(longitude: CLLocationDegrees, zoom: Int) -> Int? {
    guard zoom >= 0 && zoom <= 30, !longitude.isNaN, !longitude.isInfinite else { return nil }
    guard longitude >= -180.0 && longitude <= 180.0 else { return nil }

    let n = Double(1 << zoom)
    let x = Int(floor((longitude + 180.0) / 360.0 * n))
    guard x >= 0 && x < (1 << zoom) else { return nil }
    return x
  }

  /// Converts a WGS84 latitude into a Slippy Map tile Y coordinate at the specified zoom.
  ///
  /// Strictly adheres to the project rules:
  /// - Nil over Defaults: returns `nil` for invalid / out-of-bounds coordinates.
  /// - Physical Units: relies exclusively on `Foundation.Measurement<UnitAngle>` for radian projection.
  public static func tileY(latitude: CLLocationDegrees, zoom: Int) -> Int? {
    guard zoom >= 0 && zoom <= 30, !latitude.isNaN, !latitude.isInfinite else { return nil }
    guard latitude >= -maxMercatorLatitudeDegrees && latitude <= maxMercatorLatitudeDegrees else { return nil }

    let latAngle = Measurement<UnitAngle>(value: latitude, unit: .degrees)
    let latRadians = latAngle.converted(to: .radians).value

    let n = Double(1 << zoom)
    let secLat = 1.0 / cos(latRadians)
    guard secLat.isFinite else { return nil }

    let y = Int(floor((1.0 - log(tan(latRadians) + secLat) / .pi) / 2.0 * n))
    guard y >= 0 && y < (1 << zoom) else { return nil }
    return y
  }

  /// Converts a Slippy Map Y index back to a TMS row index.
  /// Returns `nil` if parameters are invalid.
  public static func tmsRow(slippyY: Int, zoom: Int) -> Int? {
    guard zoom >= 0 && zoom <= 30 else { return nil }
    let maxTiles = 1 << zoom
    guard slippyY >= 0 && slippyY < maxTiles else { return nil }
    return maxTiles - 1 - slippyY
  }

  /// Converts a TMS row index back to a Slippy Map Y index.
  /// Returns `nil` if parameters are invalid.
  public static func slippyY(tmsRow: Int, zoom: Int) -> Int? {
    guard zoom >= 0 && zoom <= 30 else { return nil }
    let maxTiles = 1 << zoom
    guard tmsRow >= 0 && tmsRow < maxTiles else { return nil }
    return maxTiles - 1 - tmsRow
  }

  /// Generates the list of unique Slippy Map tile coordinates covering the given bounding box at a single zoom level.
  /// Discards invalid segments without falling back to dummy defaults.
  public static func tileCoordinates(for bounds: GeographicBoundingBox, zoom: Int) -> [TileCoordinate] {
    guard zoom >= 0 && zoom <= 30 else { return [] }
    let segments = bounds.splitAtAntiMeridian()
    var tiles: Set<TileCoordinate> = []

    for segment in segments {
      guard let xMin = tileX(longitude: segment.southWest.longitude, zoom: zoom),
            let xMax = tileX(longitude: segment.northEast.longitude, zoom: zoom),
            let yMin = tileY(latitude: segment.northEast.latitude, zoom: zoom),
            let yMax = tileY(latitude: segment.southWest.latitude, zoom: zoom) else {
        continue
      }

      let xStart = min(xMin, xMax)
      let xEnd = max(xMin, xMax)
      let yStart = min(yMin, yMax)
      let yEnd = max(yMin, yMax)

      for x in xStart...xEnd {
        for y in yStart...yEnd {
          tiles.insert(TileCoordinate(zoom: zoom, x: x, y: y))
        }
      }
    }

    return tiles.sorted()
  }

  /// Generates all unique Slippy Map tile coordinates covering the bounding box across a zoom range.
  public static func allTileCoordinates(
    for bounds: GeographicBoundingBox,
    minZoom: Int,
    maxZoom: Int
  ) -> [TileCoordinate] {
    guard minZoom >= 0, minZoom <= maxZoom, maxZoom <= 30 else { return [] }
    var allTiles: [TileCoordinate] = []

    for z in minZoom...maxZoom {
      allTiles.append(contentsOf: tileCoordinates(for: bounds, zoom: z))
    }

    return allTiles
  }
}
