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
  /// Normalizes `+180.0°` to column `0` (matching `-180.0°` on the anti-meridian).
  /// Returns `nil` if inputs are invalid or outside valid bounds (Nil over Defaults).
  public static func tileX(longitude: CLLocationDegrees, zoom: Int) -> Int? {
    guard zoom >= 0 && zoom <= 30, !longitude.isNaN, !longitude.isInfinite else { return nil }
    guard longitude >= -180.0 && longitude <= 180.0 else { return nil }

    let tileCount = 1 << zoom
    if longitude == 180.0 {
      return 0
    }
    let x = Int(floor((longitude + 180.0) / 360.0 * Double(tileCount)))
    guard x >= 0 && x < tileCount else { return nil }
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

    let maxTiles = 1 << zoom
    let n = Double(maxTiles)
    let secLat = 1.0 / cos(latRadians)
    guard secLat.isFinite else { return nil }

    // Clamp normalized Mercator Y into [0, 1] after the strict ±maxMercatorLatitudeDegrees guard
    // so floating-point ULP overshoot at the exact ±85.05112878° limits maps cleanly to rows 0 and (maxTiles - 1).
    let rawNormalizedY = (1.0 - log(tan(latRadians) + secLat) / .pi) / 2.0
    guard rawNormalizedY.isFinite else { return nil }
    let normalizedY = min(1.0, max(0.0, rawNormalizedY))

    let y = min(maxTiles - 1, Int(floor(normalizedY * n)))
    guard y >= 0 && y < maxTiles else { return nil }
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

  /// Computes the Slippy Map X/Y tile index ranges for a non-anti-meridian-crossing segment.
  /// Handles the eastern boundary `northEast.longitude == 180.0` (with `southWest.longitude < 180.0`)
  /// by mapping it to the rightmost column `(1 << zoom) - 1`.
  private static func tileRanges(
    forSegment segment: GeographicBoundingBox,
    zoom: Int,
    clampLatitude: Bool
  ) -> (xRange: ClosedRange<Int>, yRange: ClosedRange<Int>)? {
    guard zoom >= 0 && zoom <= 30 else { return nil }

    let maxTileIndex = (1 << zoom) - 1
    guard let xMin = tileX(longitude: segment.southWest.longitude, zoom: zoom) else {
      return nil
    }

    let xMax: Int
    if segment.northEast.longitude == 180.0 && segment.southWest.longitude < 180.0 {
      xMax = maxTileIndex
    } else {
      guard let resolvedXMax = tileX(longitude: segment.northEast.longitude, zoom: zoom) else {
        return nil
      }
      xMax = resolvedXMax
    }

    let northLat: CLLocationDegrees
    let southLat: CLLocationDegrees
    if clampLatitude {
      northLat = min(maxMercatorLatitudeDegrees, max(-maxMercatorLatitudeDegrees, segment.northEast.latitude))
      southLat = min(maxMercatorLatitudeDegrees, max(-maxMercatorLatitudeDegrees, segment.southWest.latitude))
    } else {
      northLat = segment.northEast.latitude
      southLat = segment.southWest.latitude
    }

    guard let yMin = tileY(latitude: northLat, zoom: zoom),
          let yMax = tileY(latitude: southLat, zoom: zoom) else {
      return nil
    }

    return (min(xMin, xMax)...max(xMin, xMax), min(yMin, yMax)...max(yMin, yMax))
  }

  /// Counts the number of tiles covering the bounding box at a single zoom level in O(1) memory.
  /// Correctly splits anti-meridian crossing bounds and handles the `180.0°` eastern boundary.
  public static func tileCount(
    for bounds: GeographicBoundingBox,
    zoom: Int,
    clampLatitude: Bool = false
  ) -> Int {
    guard zoom >= 0 && zoom <= 30 else { return 0 }
    let segments = bounds.splitAtAntiMeridian()
    var count = 0

    for segment in segments {
      guard let ranges = tileRanges(forSegment: segment, zoom: zoom, clampLatitude: clampLatitude) else {
        continue
      }
      count += ranges.xRange.count * ranges.yRange.count
    }

    return count
  }

  /// Generates the list of unique Slippy Map tile coordinates covering the given bounding box at a single zoom level.
  /// Discards invalid segments without falling back to dummy defaults.
  public static func tileCoordinates(for bounds: GeographicBoundingBox, zoom: Int) -> [TileCoordinate] {
    guard zoom >= 0 && zoom <= 30 else { return [] }
    let segments = bounds.splitAtAntiMeridian()
    var tiles: Set<TileCoordinate> = []

    for segment in segments {
      guard let ranges = tileRanges(forSegment: segment, zoom: zoom, clampLatitude: false) else {
        continue
      }

      for x in ranges.xRange {
        for y in ranges.yRange {
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
