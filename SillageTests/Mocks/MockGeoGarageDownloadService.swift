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
  private var progressContinuations: [UUID: AsyncStream<Double?>.Continuation] = [:]

  var customGlobalDownloadProgress: Double? = nil

  var activeDownloads: [ActiveCAASDownload] = [] {
    didSet {
      let progress = globalDownloadProgress
      for cont in progressContinuations.values {
        cont.yield(progress)
      }
    }
  }

  var isDownloading: Bool {
    switch downloadPhase {
    case .queued, .waitingForNetwork, .requesting, .generating, .downloading:
      return true
    case .idle, .completed, .failed, .cancelled:
      return false
    }
  }

  var globalDownloadProgress: Double? {
    if let custom = customGlobalDownloadProgress {
      return custom
    }
    guard isDownloading, !activeDownloads.isEmpty else { return nil }
    let total = activeDownloads.reduce(0.0) { $0 + $1.progress }
    return total / Double(activeDownloads.count)
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

  func downloadProgressStream() -> AsyncStream<Double?> {
    let id = UUID()
    return AsyncStream { continuation in
      continuation.yield(self.globalDownloadProgress)
      self.progressContinuations[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.progressContinuations.removeValue(forKey: id)
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
