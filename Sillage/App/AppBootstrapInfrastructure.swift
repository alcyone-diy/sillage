//
//  AppBootstrapInfrastructure.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import MapLibre
import OSLog

/// Stateless low-level filesystem and network-protocol bootstrap helpers invoked by `AppEnvironment`.
enum AppBootstrapInfrastructure {

  /// Ensures the `Charts/` folder exists in `documentsDirectory`, schedules background creation
  /// of the user `ReadMe` file if absent, and schedules background cleanup of temporary GPX exports.
  nonisolated static func setupFileSystem(
    documentsDirectory: URL? = nil,
    temporaryDirectory: URL? = nil,
    fileManager: FileManager = .default
  ) throws {
    guard let docsURL = documentsDirectory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
      throw NSError(
        domain: "AppEnvironmentError",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Document directory not found"]
      )
    }

    try prepareChartsDirectory(in: docsURL, fileManager: fileManager)

    let readmeURL = docsURL.appendingPathComponent("\(AppConstants.appName)_ReadMe.txt")
    if !fileManager.fileExists(atPath: readmeURL.path) {
      Task.detached(priority: .background) {
        writeReadMeIfMissing(at: readmeURL)
      }
    }

    let resolvedTempDir = temporaryDirectory ?? fileManager.temporaryDirectory
    Task.detached(priority: .background) {
      removeGPXExportsDirectoryIfPresent(in: resolvedTempDir)
    }

    Logger.storage.debug("⚓️ FileSystem ready: \(docsURL.path, privacy: .public)")
  }

  /// Creates `<documentsDirectory>/Charts` synchronously if it does not already exist.
  nonisolated static func prepareChartsDirectory(
    in documentsDirectory: URL,
    fileManager: FileManager = .default
  ) throws {
    let chartsURL = documentsDirectory.appendingPathComponent("Charts", isDirectory: true)
    if !fileManager.fileExists(atPath: chartsURL.path) {
      try fileManager.createDirectory(at: chartsURL, withIntermediateDirectories: true)
    }
  }

  /// Writes the default `Charts` ReadMe file synchronously if it does not already exist.
  nonisolated static func writeReadMeIfMissing(
    at readmeURL: URL,
    fileManager: FileManager = .default
  ) {
    guard !fileManager.fileExists(atPath: readmeURL.path) else { return }
    let text = "\(AppConstants.appName) - Chart Plotter.\nPlease place your .mbtiles files in the 'Charts' directory."
    do {
      try text.write(to: readmeURL, atomically: true, encoding: .utf8)
    } catch {
      Logger.storage.error("❌ Failed to write ReadMe file: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Removes `<temporaryDirectory>/GPXExports` synchronously if present.
  nonisolated static func removeGPXExportsDirectoryIfPresent(
    in temporaryDirectory: URL,
    fileManager: FileManager = .default
  ) {
    let gpxTempDir = temporaryDirectory.appendingPathComponent("GPXExports", isDirectory: true)
    guard fileManager.fileExists(atPath: gpxTempDir.path) else { return }
    do {
      try fileManager.removeItem(at: gpxTempDir)
      Logger.storage.debug("🧹 GPX temporary folder cleanup successful.")
    } catch {
      Logger.storage.error("❌ Failed to clean GPX temporary folder: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Registers `TileProxyProtocol` on MapLibre's shared `URLSessionConfiguration` before any map or pack starts.
  nonisolated static func configureMapLibreProtocol() {
    guard let config = MLNNetworkConfiguration.sharedManager.sessionConfiguration else { return }
    registerTileProxyProtocol(in: config)
    MLNNetworkConfiguration.sharedManager.sessionConfiguration = config
  }

  /// Idempotently inserts `TileProxyProtocol` at index 0 of `configuration.protocolClasses`.
  nonisolated static func registerTileProxyProtocol(in configuration: URLSessionConfiguration) {
    if var protocolClasses = configuration.protocolClasses {
      if !protocolClasses.contains(where: { $0 == TileProxyProtocol.self }) {
        protocolClasses.insert(TileProxyProtocol.self, at: 0)
      }
      configuration.protocolClasses = protocolClasses
    } else {
      configuration.protocolClasses = [TileProxyProtocol.self]
    }
  }
}
