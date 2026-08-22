//
//  GeoGarageChartDownloaderProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Protocol defining the chart download, streaming MD5 validation, and local storage lifecycle.
protocol GeoGarageChartDownloaderProtocol: Sendable {
  /// Downloads a generated package archive, validates its MD5 checksum in streaming mode (1 MB chunks),
  /// moves it into `Documents/Charts/`, deletes the server package, and records the download in the repository.
  func download(
    packageID: UUID,
    downloadURL: URL,
    expectedMD5: String,
    layerID: String,
    layerName: String,
    boundsWKT: String,
    zoomMax: Int,
    apiKey: String,
    localID: UUID?
  ) async throws(CaasError) -> OfflineChartDownload

  /// Deletes the local MBTiles file from disk and removes the record from the download repository.
  func deleteLocalChart(id: UUID) async throws(CaasError)
}

extension GeoGarageChartDownloaderProtocol {
  func download(
    packageID: UUID,
    downloadURL: URL,
    expectedMD5: String,
    layerID: String,
    layerName: String,
    boundsWKT: String,
    zoomMax: Int,
    apiKey: String
  ) async throws(CaasError) -> OfflineChartDownload {
    try await download(
      packageID: packageID,
      downloadURL: downloadURL,
      expectedMD5: expectedMD5,
      layerID: layerID,
      layerName: layerName,
      boundsWKT: boundsWKT,
      zoomMax: zoomMax,
      apiKey: apiKey,
      localID: nil
    )
  }
}
