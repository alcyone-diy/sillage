//
//  MockOfflineMapManager.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
@testable import Sillage

/// A mock implementation of `OfflineMapManagerProtocol` specifically designed for unit testing.
///
/// **Why is this necessary?**
/// We must never use the concrete `OfflineMapManager` in unit tests. The concrete manager uses
/// `MLNOfflineStorage`, which relies on MapLibre's C++ core. When a unit test finishes, XCTest 
/// violently tears down the Swift context. If MapLibre's C++ threads are still executing or trying
/// to callback into Swift closures at that exact moment, it results in fatal memory corruption 
/// (`EXC_BAD_ACCESS` in `swift_task_localValuePopImpl`). 
/// By using this mock, we completely bypass MapLibre in tests, ensuring they run synchronously and safely.
@MainActor
final class MockOfflineMapManager: OfflineMapManagerProtocol {
  var isDownloading: Bool = false
  var isDownloadComplete: Bool = false
  var downloadError: Error? = nil
  var downloadProgress: Double = 0.0
  var isClearingCache: Bool = false
  var downloadedRegions: [OfflineRegionInfo] = []
  
  func downloadRegion(bounds: GeographicBoundingBox, styleURL: URL, regionName: String) {
    isDownloading = true
  }
  
  func deletePack(id: String) async throws {
    downloadedRegions.removeAll { $0.id == id }
  }
  
  var deleteAllPacksCalled = false
  func deleteAllPacks() async throws {
    deleteAllPacksCalled = true
    downloadedRegions.removeAll()
  }
  
  func cancelDownload() {
    isDownloading = false
  }
  
  func reset() {
    isDownloading = false
    isDownloadComplete = false
    downloadError = nil
    downloadProgress = 0.0
  }
  

  
  var clearAmbientCacheCalled = false
  func clearAmbientCache() async throws {
    clearAmbientCacheCalled = true
  }
}
