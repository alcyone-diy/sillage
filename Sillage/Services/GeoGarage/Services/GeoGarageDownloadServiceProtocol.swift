//
//  GeoGarageDownloadServiceProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Protocol defining the global lifecycle, orchestration, state preservation,
/// and automatic network-reconnection recovery for GeoGarage CAAS chart package downloads.
@MainActor
protocol GeoGarageDownloadServiceProtocol: AnyObject {

  /// Current observable state of the CAAS download workflow.
  var downloadPhase: GeoGarageDownloadPhaseState { get }

  /// Indicates whether a download is actively requesting, generating, downloading, or waiting for network.
  var isDownloading: Bool { get }

  /// Normalized progress value between 0.0 and 1.0 when available during package generation or downloading, or nil if indeterminate.
  var downloadProgress: Double? { get }

  /// Initiates an offline chart package generation and download pipeline.
  /// Synchronously persists the pending request before any network attempt.
  /// - Parameters:
  ///   - layerID: Unique cartography layer identifier (e.g. "shom").
  ///   - layerName: Human-readable layer name.
  ///   - zoneWKT: Bounding box in WKT POLYGON format.
  ///   - zoomMax: Maximum zoom level to include in the MBTiles archive.
  ///   - apiKey: Dedicated CAAS API key or OAuth token.
  ///   - customerID: User's GeoGarage customer identifier.
  func startDownload(
    layerID: String,
    layerName: String,
    zoneWKT: String,
    zoomMax: Int,
    apiKey: String,
    customerID: String
  )

  /// Resumes an in-flight or queued CAAS download (e.g., on app launch or upon network reconnection).
  func resumePendingDownloadIfNeeded() async

  /// Cancels any active or queued download, cleans up pending state, and resets downloadPhase.
  func cancelDownload()

  /// Explicitly marks the download as failed with a localized error message and cleans up any pending task or state.
  /// - Parameter errorMessage: Human-readable error description for UI display.
  func failDownload(with errorMessage: String)

  /// Deletes a downloaded chart package from local disk and repository.
  func deleteDownload(_ download: OfflineChartDownload) async throws(CaasError)
}
