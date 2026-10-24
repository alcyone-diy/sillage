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

  var lastCustomName: String? = nil
  var lastReplacesChartID: UUID? = nil
  var lastZoomMax: Int? = nil

  var shouldThrowOnDelete: Bool = false
  var deleteDownloadError: CaasError? = nil

  func startDownload(
    layerID: String,
    layerName: String,
    zoneWKT: String,
    zoomMax: Int?,
    accessToken: String,
    customerID: String,
    customName: String? = nil,
    replacesChartID: UUID? = nil
  ) {
    let appliedZoomMax = zoomMax ?? AppConstants.Cartography.Zoom.defaultOfflineZoomMax
    startDownloadCalled = true
    lastZoomMax = appliedZoomMax
    lastCustomName = customName
    lastReplacesChartID = replacesChartID
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

  var lastFailDownloadIsAuthError: Bool = false

  func failDownload(with errorMessage: String, isAuthenticationError: Bool) {
    failDownloadCalled = true
    lastFailDownloadIsAuthError = isAuthenticationError
    downloadPhase = .failed(errorMessage: errorMessage)
  }

  func failDownload(id: UUID, errorMessage: String, isAuthenticationError: Bool) {
    failDownloadCalled = true
    lastFailDownloadIsAuthError = isAuthenticationError
    downloadPhase = .failed(errorMessage: errorMessage)
  }

  func deleteDownload(_ download: OfflineChartDownload) async throws(CaasError) {
    if shouldThrowOnDelete {
      throw deleteDownloadError ?? .fileSystemError(underlying: "Simulated deletion failure")
    }
    deletedDownloads.append(download)
  }
}
