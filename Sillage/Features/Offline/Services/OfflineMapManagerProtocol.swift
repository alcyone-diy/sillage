//
//  OfflineMapManagerProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Protocol defining the interface for offline map management.
///
/// **Architectural Note:**
/// This protocol allows for Dependency Injection (DI) in ViewModels and Services.
/// Since the concrete implementation relies heavily on MapLibre's C++ core (which manages its own
/// disk I/O and background threads), hiding it behind this protocol ensures clean architectural boundaries
/// and allows swapping the implementation when a lightweight or decoupled environment is required.
@MainActor
protocol OfflineMapManagerProtocol: Sendable {
  var isDownloading: Bool { get }
  var isDownloadComplete: Bool { get }
  var downloadError: Error? { get }
  var downloadProgress: Double { get }
  var isClearingCache: Bool { get }
  var downloadedRegions: [OfflineRegionInfo] { get }
  var globalDownloadProgress: Double? { get }
  var totalPendingDownloads: Int { get }
  
  func downloadRegion(bounds: GeographicBoundingBox, styleURL: URL, regionName: String)
  func deletePack(id: String) async throws
  func deleteAllPacks() async throws
  func cancelDownload()
  func reset()
  func clearAmbientCache() async throws
}
