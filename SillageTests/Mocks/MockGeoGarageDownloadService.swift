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

  var activeDownloads: [ActiveCAASDownload] = []

  var isDownloading: Bool {
    switch downloadPhase {
    case .queued, .waitingForNetwork, .requesting, .generating, .downloading:
      return true
    case .idle, .completed, .failed, .cancelled:
      return false
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
  var cancelledDownloadIDs: [UUID] = []
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

  func cancelDownload(id: UUID) {
    cancelledDownloadIDs.append(id)
    cancelDownloadCalled = true
    activeDownloads.removeAll { $0.id == id }
  }

  func cancelDownload() {
    cancelDownloadCalled = true
    activeDownloads.removeAll()
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
