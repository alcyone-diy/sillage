//
//  TileFetchPipeline.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Protocol defining an agnostic pipeline for retrieving raw tile payload data.
///
/// Designed to decouple `MBTilesDownloadWorker` from concrete cartographic sources:
/// - Raster composition (e.g. OpenSeaMap blending OSM base raster with transparent seamark PNGs)
/// - Vector tiles (e.g. OpenMapTiles / Protomaps MVT / PBF)
nonisolated public protocol TileFetchPipeline: Sendable {

  /// File format identifier stored in MBTiles metadata (e.g., "png", "pbf", "jpeg").
  var format: String { get }

  /// Fetches raw tile data for the given Slippy Map XYZ coordinate.
  ///
  /// - Parameters:
  ///   - zoom: Slippy zoom level.
  ///   - x: Slippy column index (West to East).
  ///   - y: Slippy row index (North to South).
  /// - Returns: Encoded binary tile data (PNG, PBF, etc.), or `nil` if the tile has no content and can be omitted.
  /// - Throws: An error if an unrecoverable network failure or rate limit occurs.
  func fetchTileData(zoom: Int, x: Int, y: Int) async throws -> Data?
}
