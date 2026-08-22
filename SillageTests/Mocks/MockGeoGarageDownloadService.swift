//
//  MockGeoGarageDownloadService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
@testable import Sillage

/// A test mock conforming to `GeoGarageDownloadServiceProtocol` for isolated unit tests.
@MainActor
final class MockGeoGarageDownloadService: GeoGarageDownloadServiceProtocol {
  var downloadPhase: GeoGarageDownloadPhaseState = .idle {
    didSet {
      for cont in continuations.values {
        cont.yield(downloadPhase)
      }
    }
  }

  private var continuations: [UUID: AsyncStream<GeoGarageDownloadPhaseState>.Continuation] = [:]

  var pendingDownload: PendingCAASDownload?

  var isDownloading: Bool {
    switch downloadPhase {
    case .waitingForNetwork, .requesting, .generating, .downloading:
      return true
    case .idle, .completed, .failed, .cancelled:
      return false
    }
  }

  var downloadProgress: Double? {
    switch downloadPhase {
    case .generating(let progress, _):
      guard let progress else { return nil }
      return min(max(progress, 0.0), 1.0)
    case .downloading(let receivedBytes, let totalBytes):
      guard totalBytes > 0 else { return nil }
      let ratio = Double(receivedBytes) / Double(totalBytes)
      return min(max(ratio, 0.0), 1.0)
    case .idle, .waitingForNetwork, .requesting, .completed, .failed, .cancelled:
      return nil
    }
  }

  func downloadStateStream() -> AsyncStream<GeoGarageDownloadPhaseState> {
    let id = UUID()
    return AsyncStream { continuation in
      continuation.yield(self.downloadPhase)
      self.continuations[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.continuations.removeValue(forKey: id)
        }
      }
    }
  }

  var startDownloadCalled = false
  var resumePendingDownloadCalled = false
  var cancelDownloadCalled = false
  var failDownloadCalled = false
  var deletedDownloads: [OfflineChartDownload] = []

  func startDownload(
    layerID: String,
    layerName: String,
    zoneWKT: String,
    zoomMax: Int,
    apiKey: String,
    customerID: String
  ) {
    startDownloadCalled = true
  }

  func resumePendingDownloadIfNeeded() async {
    resumePendingDownloadCalled = true
  }

  func cancelDownload() {
    cancelDownloadCalled = true
    downloadPhase = .cancelled
  }

  func failDownload(with errorMessage: String) {
    failDownloadCalled = true
    downloadPhase = .failed(errorMessage: errorMessage)
  }

  func deleteDownload(_ download: OfflineChartDownload) async throws(CaasError) {
    deletedDownloads.append(download)
  }
}
