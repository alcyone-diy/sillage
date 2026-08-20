//
//  GeoGarageOfflineTileProviderProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Defines the contract for providing offline raster tile data directly from downloaded SQLCipher packages.
protocol GeoGarageOfflineTileProviderProtocol: Sendable {
  /// Concurrently retrieves decrypted tile bytes for a given layer ID and XYZ coordinates.
  /// - Parameters:
  ///   - layerID: GeoGarage layer identifier (e.g. "shom", "ukho").
  ///   - z: Zoom level.
  ///   - x: Tile column.
  ///   - y: Tile row.
  /// - Returns: Decrypted tile data if found in any downloaded package for the layer, or `nil`.
  func tile(layerID: String, z: Int, x: Int, y: Int) async -> Data?

  /// Synchronizes active offline packages and readers with the current download registry.
  /// - Parameters:
  ///   - downloads: Array of downloaded offline packages.
  ///   - sharedSecret: Partner shared secret for key derivation.
  ///   - customerID: User customer ID for key derivation.
  func reloadDownloads(
    _ downloads: [OfflineChartDownload],
    sharedSecret: String,
    customerID: String
  ) async

  /// Closes all active database readers and releases all resources.
  func close() async
}
