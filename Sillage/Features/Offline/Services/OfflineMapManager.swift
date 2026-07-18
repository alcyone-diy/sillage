//
//  OfflineMapManager.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import UIKit
import MapLibre
import OSLog
import Observation

private struct OfflinePackContext: Codable {
  let id: String
  let regionName: String
}

enum MapConstants {
  static let ambientCacheSize: UInt64 = 524_288_000
}

struct OfflineRegionInfo: Identifiable, Equatable {
  let id: String
  let name: String
  let sizeInBytes: UInt64
}

@Observable
@MainActor
final class OfflineMapManager {
  
  var isDownloading: Bool = false
  var isDownloadComplete: Bool = false
  var isClearingCache: Bool = false
  var downloadProgress: Double = 0.0
  var downloadError: String? = nil
  var downloadedRegions: [OfflineRegionInfo] = []
  
  private var progressObservationTask: Task<Void, Never>?
  private var errorObservationTask: Task<Void, Never>?
  private var activePack: MLNOfflinePack?
  private var packsObservation: NSKeyValueObservation?
  
  init() {
    MLNOfflineStorage.shared.setMaximumAllowedMapboxTiles(UInt64.max)
    MLNOfflineStorage.shared.setMaximumAmbientCacheSize(UInt(MapConstants.ambientCacheSize), withCompletionHandler: { error in
      if let error = error {
        Logger.offline.error("Failed to set maximum ambient cache size: \(error.localizedDescription, privacy: .public)")
      } else {
        let sizeMB = MapConstants.ambientCacheSize / 1024 / 1024
        Logger.offline.info("Successfully set maximum ambient cache size to \(sizeMB, privacy: .public)MB")
      }
    })
    
    // MLNOfflineStorage loads the database asynchronously on launch.
    // packs is nil initially, so we must observe it via KVO to know when it's ready.
    packsObservation = MLNOfflineStorage.shared.observe(\.packs, options: [.initial, .new]) { [weak self] _, _ in
      Task { @MainActor [weak self] in
        self?.loadExistingPacks()
      }
    }
    
    // Globally observe progress changes to update sizes of completed packs
    // when requestProgress() is called.
    Task { [weak self] in
      for await notification in NotificationCenter.default.notifications(named: NSNotification.Name.MLNOfflinePackProgressChanged) {
        guard !Task.isCancelled else { break }
        guard let self = self, let pack = notification.object as? MLNOfflinePack else { continue }
        Task { @MainActor [weak self] in
          self?.updateRegionSize(for: pack)
        }
      }
    }
  }
  
  func loadExistingPacks() {
    guard let packs = MLNOfflineStorage.shared.packs else { return }
    var regions: [OfflineRegionInfo] = []
    let decoder = JSONDecoder()
    for pack in packs {
      let contextData = pack.context
      if let context = try? decoder.decode(OfflinePackContext.self, from: contextData) {
        let size = pack.progress.countOfBytesCompleted
        regions.append(OfflineRegionInfo(id: context.id, name: context.regionName, sizeInBytes: size))
        // Force MapLibre to recalculate the size from the database
        pack.requestProgress()
      }
    }
    self.downloadedRegions = regions
  }
  
  private func updateRegionSize(for pack: MLNOfflinePack) {
    let decoder = JSONDecoder()
    guard let context = try? decoder.decode(OfflinePackContext.self, from: pack.context) else { return }
    
    if let index = downloadedRegions.firstIndex(where: { $0.id == context.id }) {
      let newSize = pack.progress.countOfBytesCompleted
      if downloadedRegions[index].sizeInBytes != newSize {
        downloadedRegions[index] = OfflineRegionInfo(id: context.id, name: context.regionName, sizeInBytes: newSize)
      }
    }
  }
  
  func deletePack(id: String) {
    guard let packs = MLNOfflineStorage.shared.packs else { return }
    let decoder = JSONDecoder()
    
    for pack in packs {
      let contextData = pack.context
      if let context = try? decoder.decode(OfflinePackContext.self, from: contextData), context.id == id {
        MLNOfflineStorage.shared.removePack(pack) { [weak self] error in
          Task { @MainActor [weak self] in
            if let error = error {
              Logger.offline.error("Failed to remove offline pack: \(error.localizedDescription, privacy: .public)")
            } else {
              self?.loadExistingPacks()
            }
          }
        }
        break
      }
    }
  }
  
  func downloadRegion(bounds: GeographicBoundingBox, styleURL: URL, regionName: String) {
    guard !isDownloading else { return }
    
    isDownloading = true
    downloadError = nil
    
    let coordinateBounds = MLNCoordinateBounds(sw: bounds.southWest, ne: bounds.northEast)
    let region = MLNTilePyramidOfflineRegion(styleURL: styleURL, bounds: coordinateBounds, fromZoomLevel: AppConstants.Cartography.Zoom.offlineMinimum, toZoomLevel: AppConstants.Cartography.Zoom.offlineMaximum)
    
    let context = OfflinePackContext(id: UUID().uuidString, regionName: regionName)
    guard let contextData = try? JSONEncoder().encode(context) else {
      Logger.offline.error("Failed to encode offline region context")
      isDownloading = false
      downloadError = "Internal error encoding context."
      return
    }
    
    MLNOfflineStorage.shared.addPack(for: region, withContext: contextData) { [weak self] pack, error in
      Task { @MainActor [weak self] in
        if let error = error {
          Logger.offline.error("Failed to add offline pack: \(error.localizedDescription, privacy: .public)")
          self?.isDownloading = false
          self?.downloadError = "Unable to start download: \(error.localizedDescription)"
          return
        }
        
        guard let pack = pack else {
          Logger.offline.error("Failed to add offline pack: pack is nil")
          self?.isDownloading = false
          self?.downloadError = "Unable to start download: Unknown error."
          return
        }
        
        self?.handlePackAdded(pack, regionName: regionName)
      }
    }
  }
  
  private func handlePackAdded(_ pack: MLNOfflinePack, regionName: String) {
    Logger.offline.info("Successfully added offline pack for region: \(regionName, privacy: .public)")
    self.activePack = pack
    self.isDownloadComplete = false
    self.downloadError = nil
    UIApplication.shared.isIdleTimerDisabled = true
    pack.resume()
    
    self.startObservingProgress()
  }
  
  func cancelDownload() {
    progressObservationTask?.cancel()
    errorObservationTask?.cancel()
    
    if let pack = activePack {
      pack.suspend()
      MLNOfflineStorage.shared.removePack(pack) { error in
        if let error = error {
          Logger.offline.error("Failed to remove offline pack: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
    
    isDownloading = false
    isDownloadComplete = false
    activePack = nil
    downloadProgress = 0.0
    UIApplication.shared.isIdleTimerDisabled = false
    
    progressObservationTask = nil
    errorObservationTask = nil
  }
  
  func reset() {
    isDownloadComplete = false
    downloadError = nil
    downloadProgress = 0.0
  }
  
  private func startObservingProgress() {
    progressObservationTask?.cancel()
    errorObservationTask?.cancel()
    
    errorObservationTask = Task { [weak self] in
      for await notification in NotificationCenter.default.notifications(named: NSNotification.Name.MLNOfflinePackError) {
        guard !Task.isCancelled else { break }
        guard let self = self else { break }
        
        guard let pack = notification.object as? MLNOfflinePack,
              pack == self.activePack,
              self.activePack != nil else { continue }
        
        let error = notification.userInfo?[MLNOfflinePackUserInfoKey.error] as? Error
        Logger.offline.error("Offline pack encountered an error: \(error?.localizedDescription ?? "", privacy: .public)")
        pack.suspend()
        self.handlePackError(error)
        break
      }
      self?.clearErrorTask()
    }
    
    progressObservationTask = Task { [weak self] in
      var lastProgress: Double = 0.0
      
      for await notification in NotificationCenter.default.notifications(named: NSNotification.Name.MLNOfflinePackProgressChanged) {
        guard !Task.isCancelled else { break }
        
        guard let self = self else { break }
        
        guard let pack = notification.object as? MLNOfflinePack,
              pack == self.activePack,
              self.activePack != nil else {
          continue
        }
        
        if pack.state == .invalid {
          Logger.offline.error("Offline pack download invalidated due to network error.")
          pack.suspend()
          self.handlePackInvalid()
          break
        }
        
        if pack.state == .complete {
          Logger.offline.info("Offline pack download completed")
          self.handlePackComplete()
          break
        }
        
        let progress = pack.progress
        let expected = Double(progress.countOfResourcesExpected)
        guard expected > 0 else { continue }
        
        let completed = Double(progress.countOfResourcesCompleted)
        let currentProgress = completed / expected
        
        if currentProgress - lastProgress >= 0.01 {
          lastProgress = currentProgress
          self.updateProgress(currentProgress)
        }
      }
      
      self?.clearProgressTask()
    }
  }
  
  private func handlePackError(_ error: Error?) {
    self.isDownloading = false
    self.downloadError = error?.localizedDescription ?? "An unknown error occurred."
    self.activePack = nil
    UIApplication.shared.isIdleTimerDisabled = false
    self.progressObservationTask?.cancel()
  }
  
  private func handlePackInvalid() {
    self.isDownloading = false
    self.downloadError = "Download interrupted."
    self.activePack = nil
    UIApplication.shared.isIdleTimerDisabled = false
    self.errorObservationTask?.cancel()
  }
  
  private func handlePackComplete() {
    self.downloadProgress = 1.0
    self.isDownloading = false
    self.isDownloadComplete = true
    self.activePack = nil
    self.loadExistingPacks()
    UIApplication.shared.isIdleTimerDisabled = false
    self.errorObservationTask?.cancel()
  }
  
  private func updateProgress(_ currentProgress: Double) {
    self.downloadProgress = currentProgress
  }
  
  private func clearErrorTask() {
    self.errorObservationTask = nil
  }
  
  private func clearProgressTask() {
    self.progressObservationTask = nil
  }
  
  @MainActor
  func clearAmbientCache() async throws {
    guard !isClearingCache else { return }
    isClearingCache = true
    defer { isClearingCache = false }
    
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      MLNOfflineStorage.shared.clearAmbientCache { @Sendable error in
        if let error = error {
          Logger.offline.error("Failed to clear ambient cache: \(error.localizedDescription, privacy: .public)")
          continuation.resume(throwing: error)
        } else {
          Logger.offline.info("Ambient cache cleared successfully.")
          continuation.resume(returning: ())
        }
      }
    }
  }
}
