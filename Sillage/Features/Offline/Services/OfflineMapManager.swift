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


enum MapConstants {
  static let ambientCacheSize: UInt64 = 524_288_000
}

struct OfflineRegionInfo: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let sizeInBytes: UInt64
  let isComplete: Bool
  let progress: Double?
  let expectedResources: UInt64
  let completedResources: UInt64
  let estimatedTimeRemaining: TimeInterval?
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
  var downloadResourcesPerSecond: Double = 0.0
  
  var totalDownloadedSize: Int64 {
    downloadedRegions.reduce(0) { $0 + Int64($1.sizeInBytes) }
  }
  
  var activeDownloadIndex: Int? {
    downloadedRegions.firstIndex(where: { !$0.isComplete })
  }
  
  var totalPendingDownloads: Int {
    downloadedRegions.filter { !$0.isComplete }.count
  }
  
  var globalDownloadProgress: Double? {
    let incomplete = downloadedRegions.filter { !$0.isComplete }
    let expected = incomplete.reduce(0) { $0 + $1.expectedResources }
    let completed = incomplete.reduce(0) { $0 + $1.completedResources }
    guard expected > 0 else { return nil }
    return Double(completed) / Double(expected)
  }
  
  var totalEstimatedTimeRemaining: TimeInterval? {
    guard downloadResourcesPerSecond > 0 else { return nil }
    let incomplete = downloadedRegions.filter { !$0.isComplete }
    let expected = incomplete.reduce(0) { $0 + $1.expectedResources }
    let completed = incomplete.reduce(0) { $0 + $1.completedResources }
    if expected > completed {
      return Double(expected - completed) / downloadResourcesPerSecond
    }
    return nil
  }
  
  private var progressObservationTask: Task<Void, Never>?
  private var errorObservationTask: Task<Void, Never>?
  private var activePack: MLNOfflinePack?
  private var packsObservation: NSKeyValueObservation?

  /// Shared decoder — allocated once, reused on the `@MainActor` for all hot-path
  /// JSON decoding (`loadExistingPacks`, `tryAutoResumeIfNeeded`).
  private let contextDecoder = JSONDecoder()

  /// Maps a live `MLNOfflinePack` instance to its decoded `OfflinePackContext`.
  /// Populated during `loadExistingPacks` so that `updateRegionSize` can resolve
  /// a pack's identity with an O(1) lookup instead of a JSON decode on every
  /// high-frequency `MLNOfflinePackProgressChanged` notification.
  private var packContextCache: [ObjectIdentifier: OfflinePackContext] = [:]

  /// Set to `true` when `loadExistingPacks` encounters packs whose state is
  /// still `.unknown` (MapLibre DB not yet resolved). The global
  /// `MLNOfflinePackProgressChanged` observer consumes this flag exactly once,
  /// triggering `tryAutoResumeIfNeeded` when the first state resolves —
  /// without running the check on every subsequent notification.
  /// Explicit `@MainActor` annotation prevents concurrent mutation from
  /// nonisolated contexts on this `@unchecked Sendable` class.
  @MainActor private var needsInitialAutoResume: Bool = false
  
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
    // The `needsInitialAutoResume` flag is consumed at most once here, after
    // requestProgress() resolves a pack's state out of `.unknown`. This avoids
    // running any logic on every high-frequency progress notification.
    Task { [weak self] in
      for await notification in NotificationCenter.default.notifications(named: NSNotification.Name.MLNOfflinePackProgressChanged) {
        guard !Task.isCancelled else { break }
        guard let self = self else { break }
        guard let pack = notification.object as? MLNOfflinePack else { continue }
        Task { @MainActor [weak self] in
          self?.updateRegionSize(for: pack)
          guard self?.needsInitialAutoResume == true else { return }
          self?.needsInitialAutoResume = false
          self?.tryAutoResumeIfNeeded()
        }
      }
    }
  }
  
  @MainActor func loadExistingPacks() {
    guard let packs = MLNOfflineStorage.shared.packs else { return }
    var regions: [OfflineRegionInfo] = []
    var newCache: [ObjectIdentifier: OfflinePackContext] = [:]
    var nextPackToResume: (pack: MLNOfflinePack, context: OfflinePackContext)? = nil
    var hadUnknownStatePacks = false

    for pack in packs {
      let contextData = pack.context
      if let context = try? contextDecoder.decode(OfflinePackContext.self, from: contextData) {
        newCache[ObjectIdentifier(pack)] = context

        let size = pack.progress.countOfBytesCompleted
        let expected = pack.progress.countOfResourcesExpected
        let completed = pack.progress.countOfResourcesCompleted
        let isComplete = pack.state == .complete || (expected > 0 && completed >= expected)
        let progress = (!isComplete && expected > 0) ? Double(completed) / Double(expected) : nil

        regions.append(OfflineRegionInfo(id: context.id, name: context.regionName, sizeInBytes: size, isComplete: isComplete, progress: progress, expectedResources: expected, completedResources: completed, estimatedTimeRemaining: nil))

        if !isComplete {
          // Force MapLibre to recalculate the size from the database only for incomplete packs
          pack.requestProgress()

          if pack.state == .unknown {
            // State not yet resolved from the async DB load; requestProgress()
            // will fire MLNOfflinePackProgressChanged once resolved, at which
            // point needsInitialAutoResume triggers a one-shot resume check.
            hadUnknownStatePacks = true
          } else {
            // State is already known — evaluate immediately.
            let isVerifiablyIncomplete = (expected > 0 && completed < expected)
            let isResumable = isVerifiablyIncomplete || pack.state == .inactive || pack.state == .invalid
            if isResumable && nextPackToResume == nil {
              nextPackToResume = (pack, context)
            }
          }
        }
      }
    }
    self.packContextCache = newCache
    self.downloadedRegions = regions

    // Auto-resume the next pack in the queue if none is currently active
    if self.activePack == nil, let next = nextPackToResume {
      Logger.offline.info("Auto-resuming pack from queue: \(next.context.regionName, privacy: .public)")
      self.activePack = next.pack
      self.isDownloading = true
      self.isDownloadComplete = false
      self.downloadProgress = 0.0
      self.updateIdleTimerState()
      self.downloadResourcesPerSecond = 0.0
      self.startObservingProgress()
      next.pack.resume()
    } else if self.activePack == nil && hadUnknownStatePacks {
      // Some packs were still in .unknown state. Arm the flag so the global
      // observer triggers a resume check as soon as the first state resolves.
      self.needsInitialAutoResume = true
    }
  }
  
  /// Resumes the first incomplete, non-queued pack if no download is active.
  /// Triggered once via `needsInitialAutoResume` after MapLibre resolves pack
  /// states from its async DB load (packs start as `.unknown` at boot).
  @MainActor
  private func tryAutoResumeIfNeeded() {
    guard activePack == nil, !isDownloading else { return }
    guard let packs = MLNOfflineStorage.shared.packs else { return }

    for pack in packs {
      // Use the in-memory cache — no JSON decode in this path.
      guard let context = packContextCache[ObjectIdentifier(pack)] else { continue }
      let expected = pack.progress.countOfResourcesExpected
      let completed = pack.progress.countOfResourcesCompleted
      let isComplete = pack.state == .complete || (expected > 0 && completed >= expected)
      guard !isComplete else { continue }

      let isVerifiablyIncomplete = (expected > 0 && completed < expected)
      let isResumable = isVerifiablyIncomplete || pack.state == .inactive || pack.state == .invalid

      if isResumable {
        Logger.offline.info("Auto-resuming pack from queue: \(context.regionName, privacy: .public)")
        self.activePack = pack
        self.isDownloading = true
        self.isDownloadComplete = false
        self.downloadProgress = 0.0
        self.updateIdleTimerState()
        self.downloadResourcesPerSecond = 0.0
        self.startObservingProgress()
        pack.resume()
        return
      }
    }
  }
  
  private func updateRegionSize(for pack: MLNOfflinePack) {
    // O(1) lookup — no JSON decode on the high-frequency progress tick.
    guard let context = packContextCache[ObjectIdentifier(pack)],
          let index = downloadedRegions.firstIndex(where: { $0.id == context.id }) else { return }

    let newSize = pack.progress.countOfBytesCompleted
    let expected = pack.progress.countOfResourcesExpected
    let completed = pack.progress.countOfResourcesCompleted
    let isComplete = pack.state == .complete || (expected > 0 && completed >= expected)
    let progress = (!isComplete && expected > 0) ? Double(completed) / Double(expected) : nil

    let newRegion = OfflineRegionInfo(id: context.id, name: context.regionName, sizeInBytes: newSize, isComplete: isComplete, progress: progress, expectedResources: expected, completedResources: completed, estimatedTimeRemaining: downloadedRegions[index].estimatedTimeRemaining)

    if downloadedRegions[index] != newRegion {
      downloadedRegions[index] = newRegion
    }
  }
  
  nonisolated func deletePack(id: String) async throws {
    let packToRemove: MLNOfflinePack? = await Task.detached {
      guard let packs = MLNOfflineStorage.shared.packs else { return nil }
      // Local decoder: JSONDecoder is not Sendable, so it cannot be captured
      // from the @MainActor-isolated contextDecoder across the Task.detached boundary.
      // Allocation cost is negligible for this infrequent deletion path.
      let decoder = JSONDecoder()

      for pack in packs {
        let contextData = pack.context
        if let context = try? decoder.decode(OfflinePackContext.self, from: contextData), context.id == id {
          return pack
        }
      }
      return nil
    }.value
    
    guard let pack = packToRemove else {
      throw OfflineMapManagerError.unknown
    }
    
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      MLNOfflineStorage.shared.removePack(pack) { error in
        if let error = error {
          continuation.resume(throwing: OfflineMapManagerError.sdkError(error))
        } else {
          continuation.resume()
        }
      }
    }
    
    await loadExistingPacks()
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
    self.downloadResourcesPerSecond = 0.0
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
      downloadResourcesPerSecond = 0.0
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
      downloadResourcesPerSecond = 0.0
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
    
    progressObservationTask = Task { @MainActor [weak self] in
      var lastProgress: Double = 0.0
      var lastDate = Date()
      var lastCompletedResources: UInt64? = nil
      
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
        let completedUInt = progress.countOfResourcesCompleted
        guard expected > 0 else { continue }
        
        if lastCompletedResources == nil {
          lastCompletedResources = completedUInt
          lastDate = Date()
        } else {
          let now = Date()
          let timeDelta = now.timeIntervalSince(lastDate)
          if timeDelta >= 1.0 {
            if let lastCompleted = lastCompletedResources {
              let delta = Double(completedUInt) - Double(lastCompleted)
              if delta >= 0 {
                let rps = delta / timeDelta
                if self.downloadResourcesPerSecond == 0 {
                  self.downloadResourcesPerSecond = rps
                } else {
                  self.downloadResourcesPerSecond = self.downloadResourcesPerSecond * 0.8 + rps * 0.2
                }
                self.recalculateETAs()
              }
            }
            lastCompletedResources = completedUInt
            lastDate = now
          }
        }
        
        let completed = Double(completedUInt)
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
  
  private func recalculateETAs() {
    guard downloadResourcesPerSecond > 0 else { return }
    
    var updatedRegions = downloadedRegions
    
    for i in 0..<updatedRegions.count {
      let region = updatedRegions[i]
      if region.isComplete {
        continue
      }
      
      let expected = region.expectedResources
      let completed = region.completedResources
      
      if expected > completed {
        let remaining = expected - completed
        let eta = Double(remaining) / downloadResourcesPerSecond
        updatedRegions[i] = OfflineRegionInfo(
          id: region.id,
          name: region.name,
          sizeInBytes: region.sizeInBytes,
          isComplete: region.isComplete,
          progress: region.progress,
          expectedResources: region.expectedResources,
          completedResources: region.completedResources,
          estimatedTimeRemaining: eta
        )
      }
    }
    self.downloadedRegions = updatedRegions
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
