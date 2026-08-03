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
import os
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

public enum OfflineMapManagerError: LocalizedError {
  case encodingFailed
  case downloadInterrupted
  case unknown
  case sdkError(Error)
  
  public var errorDescription: String? {
    switch self {
    case .encodingFailed: return String(localized: "Internal error encoding context.")
    case .downloadInterrupted: return String(localized: "Download interrupted.")
    case .unknown: return String(localized: "An unknown error occurred.")
    case .sdkError(let error): return error.localizedDescription
    }
  }
}

@Observable
@MainActor
public final class OfflineMapManager: OfflineMapManagerProtocol, @unchecked Sendable {
  
  var isDownloading: Bool = false
  var isDownloadComplete: Bool = false
  var isClearingCache: Bool = false
  var downloadProgress: Double = 0.0
  var downloadError: Error? = nil
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
    var nextPackToResume: (pack: MLNOfflinePack, context: OfflinePackContext)? = nil
    
    for pack in packs {
      let contextData = pack.context
      if let context = try? decoder.decode(OfflinePackContext.self, from: contextData) {
        let size = pack.progress.countOfBytesCompleted
        regions.append(OfflineRegionInfo(id: context.id, name: context.regionName, sizeInBytes: size))
        
        if pack.state != .complete {
          // Force MapLibre to recalculate the size from the database only for incomplete packs
          pack.requestProgress()
          
          if pack.state != .invalid && nextPackToResume == nil {
            nextPackToResume = (pack, context)
          }
        }
      }
    }
    self.downloadedRegions = regions
    
    // Auto-resume the next pack in the queue if none is currently active
    if self.activePack == nil, let next = nextPackToResume {
      Logger.offline.info("Auto-resuming pack from queue: \(next.context.regionName, privacy: .public)")
      self.activePack = next.pack
      self.isDownloading = true
      self.isDownloadComplete = false
      self.downloadProgress = 0.0
      self.updateIdleTimerState()
      self.startObservingProgress()
      next.pack.resume()
    }
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
  
  func deleteAllPacks() async throws {
    guard let packs = MLNOfflineStorage.shared.packs, !packs.isEmpty else {
      self.downloadedRegions = []
      try? await self.clearAmbientCache()
      return
    }
    var encounteredError: Error?
    
    for pack in packs {
      do {
        let _: Void = try await withTimeoutContinuation(timeoutSeconds: 2.0) { resume in
          MLNOfflineStorage.shared.removePack(pack) { error in
            if let error = error {
              resume(.failure(error))
            } else {
              resume(.success(()))
            }
          }
        }
      } catch {
        Logger.offline.error("Failed to remove an offline pack during mass deletion: \(error.localizedDescription, privacy: .public)")
        if encounteredError == nil {
          encounteredError = error
        }
      }
    }
    
    if let error = encounteredError {
      self.loadExistingPacks()
      throw error
    } else {
      self.downloadedRegions = []
    }
  }
  
  func downloadRegion(bounds: GeographicBoundingBox, styleURL: URL, regionName: String) {
    isDownloading = true
    downloadError = nil
    
    let coordinateBounds = MLNCoordinateBounds(sw: bounds.southWest, ne: bounds.northEast)
    let region = MLNTilePyramidOfflineRegion(styleURL: styleURL, bounds: coordinateBounds, fromZoomLevel: AppConstants.Cartography.Zoom.offlineMinimum, toZoomLevel: AppConstants.Cartography.Zoom.offlineMaximum)
    
    let context = OfflinePackContext(id: UUID().uuidString, regionName: regionName)
    guard let contextData = try? JSONEncoder().encode(context) else {
      Logger.offline.error("Failed to encode offline region context")
      isDownloading = false
      downloadError = OfflineMapManagerError.encodingFailed
      return
    }
    
    MLNOfflineStorage.shared.addPack(for: region, withContext: contextData) { [weak self] pack, error in
      Task { @MainActor [weak self] in
        if let error = error {
          Logger.offline.error("Failed to add offline pack: \(error.localizedDescription, privacy: .public)")
          self?.isDownloading = false
          self?.downloadError = error
          return
        }
        
        guard let pack = pack else {
          Logger.offline.error("Failed to add offline pack: pack is nil")
          self?.isDownloading = false
          self?.downloadError = OfflineMapManagerError.unknown
          return
        }
        
        self?.handlePackAdded(pack, regionName: regionName)
      }
    }
  }
  
  private func handlePackAdded(_ pack: MLNOfflinePack, regionName: String) {
    Logger.offline.info("Successfully added offline pack for region: \(regionName, privacy: .public)")
    
    if self.activePack != nil {
      Logger.offline.info("A download is already active, adding to queue.")
      self.loadExistingPacks()
      return
    }
    
    self.activePack = pack
    self.isDownloadComplete = false
    self.downloadError = nil
    self.updateIdleTimerState()
    pack.resume()
    
    self.startObservingProgress()
  }
  
  func cancelDownload() {
    progressObservationTask?.cancel()
    errorObservationTask?.cancel()
    progressObservationTask = nil
    errorObservationTask = nil
    
    if let pack = activePack {
      pack.suspend()
      
      isDownloading = false
      isDownloadComplete = false
      activePack = nil
      downloadProgress = 0.0
      self.updateIdleTimerState()
      
      MLNOfflineStorage.shared.removePack(pack) { [weak self] error in
        Task { @MainActor [weak self] in
          if let error = error {
            Logger.offline.error("Failed to remove offline pack: \(error.localizedDescription, privacy: .public)")
          }
          self?.loadExistingPacks()
        }
      }
    } else {
      isDownloading = false
      isDownloadComplete = false
      activePack = nil
      downloadProgress = 0.0
      self.updateIdleTimerState()
      self.loadExistingPacks()
    }
  }
  
  func reset() {
    isDownloadComplete = false
    downloadError = nil
    downloadProgress = 0.0
  }
  
  private func updateIdleTimerState() {
    UIApplication.shared.isIdleTimerDisabled = (self.activePack != nil)
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
    self.downloadError = error ?? OfflineMapManagerError.unknown
    self.activePack = nil
    self.updateIdleTimerState()
    self.progressObservationTask?.cancel()
  }
  
  private func handlePackInvalid() {
    self.isDownloading = false
    self.downloadError = OfflineMapManagerError.downloadInterrupted
    self.activePack = nil
    self.updateIdleTimerState()
    self.errorObservationTask?.cancel()
  }
  
  private func handlePackComplete() {
    self.downloadProgress = 1.0
    self.isDownloadComplete = true
    self.activePack = nil
    self.errorObservationTask?.cancel()
    
    // This will automatically pick up the next pack in the queue if one exists
    self.loadExistingPacks()
    
    if self.activePack == nil {
      self.isDownloading = false
    }
    self.updateIdleTimerState()
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
    
    do {
      let _: Void = try await withTimeoutContinuation(timeoutSeconds: 2.0) { resume in
        MLNOfflineStorage.shared.clearAmbientCache { @Sendable error in
          if let error = error {
            resume(.failure(error))
          } else {
            resume(.success(()))
          }
        }
      }
      Logger.offline.info("Ambient cache cleared successfully.")
    } catch {
      Logger.offline.error("Failed to clear ambient cache: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }
}

/// A robust wrapper for `CheckedContinuation` specifically designed to mitigate a known flaw
/// in the MapLibre SDK where completion handlers are occasionally dropped silently.
/// 
/// MapLibre's C++ core can sometimes destroy a block without executing it (e.g., when the ambient 
/// cache is corrupted). If a Swift continuation is captured in that block and dropped, it triggers 
/// a fatal `SIGABRT` (leaked continuation crash).
///
/// **Why an `actor`?**
/// We use a Swift 6 `actor` (`ContinuationManager`) instead of a lock (`OSAllocatedUnfairLock`) 
/// to manage the continuation. When a lock (which is a struct) is captured in an escaping closure 
/// that goes into MapLibre's C++ boundary, Swift creates a copy of the struct. If the Swift task 
/// environment is abruptly cancelled or torn down while C++ still holds that closure, it can cause 
/// memory corruption (`EXC_BAD_ACCESS`). An `actor` provides native, safe memory isolation 
/// without struct copying, completely eliminating this class of crashes.
private actor ContinuationManager<T: Sendable> {
  private var continuation: CheckedContinuation<T, Error>?
  
  init(_ continuation: CheckedContinuation<T, Error>) {
    self.continuation = continuation
  }
  
  func resume(with result: Result<T, Error>) {
    if let cont = continuation {
      cont.resume(with: result)
      continuation = nil
    }
  }
}

private func withTimeoutContinuation<T: Sendable>(
  timeoutSeconds: TimeInterval,
  operation: @escaping @Sendable (@escaping @Sendable (Result<T, Error>) -> Void) -> Void
) async throws -> T {
  try await withCheckedThrowingContinuation { continuation in
    let manager = ContinuationManager(continuation)
    
    let resume: @Sendable (Result<T, Error>) -> Void = { result in
      Task {
        await manager.resume(with: result)
      }
    }
    
    Task {
      try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
      Logger.offline.error("MapLibre C++ callback timed out after \(timeoutSeconds, privacy: .public) seconds. Forcing continuation resumption.")
      await manager.resume(with: .failure(NSError(
        domain: "OfflineMapManager",
        code: -998,
        userInfo: [NSLocalizedDescriptionKey: "MapLibre operation timed out without calling the completion handler."]
      )))
    }
    
    operation(resume)
  }
}
