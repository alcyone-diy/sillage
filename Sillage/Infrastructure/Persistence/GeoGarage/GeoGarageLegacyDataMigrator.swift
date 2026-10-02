//
//  GeoGarageLegacyDataMigrator.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB
import OSLog

/// A Swift 6 actor dedicated to migrating legacy `geogarage_downloads.json` data into SQLite.
///
/// **Design Principles**:
/// - **Single Responsibility (SRP)**: Strictly isolated ETL component. All legacy JSON parsing,
///   DTO structures, and file archiving live exclusively here.
/// - **Concurrency**: Asynchronous I/O and JSON decoding are fully isolated within this actor,
///   never blocking `@MainActor` or occupying a SQLite transaction lock during decode.
/// - **Ephemeral**: Designed to be removable in future versions without touching repository logic.
actor GeoGarageLegacyDataMigrator {
  private let databaseManager: DatabaseManager
  private let sourceFileURL: URL
  private let fileManager: FileManager

  init(
    databaseManager: DatabaseManager,
    sourceFileURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.databaseManager = databaseManager
    self.fileManager = fileManager

    if let sourceFileURL {
      self.sourceFileURL = sourceFileURL
    } else if let documentsDir = fileManager.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first {
      self.sourceFileURL = documentsDir.appendingPathComponent("geogarage_downloads.json")
    } else {
      self.sourceFileURL = fileManager.temporaryDirectory
        .appendingPathComponent("geogarage_downloads.json")
    }
  }

  /// Migrates data from `geogarage_downloads.json` into SQLite if the file exists.
  ///
  /// Execution steps:
  /// 1. Check if source file exists. If not, exit immediately.
  /// 2. Read raw `Data` and decode into legacy DTOs outside of the DB transaction.
  /// 3. Map DTOs to `GeoGarageDownloadRecord`.
  /// 4. Insert or update into database using `record.save(db)`.
  /// 5. Rename source file to `geogarage_downloads.json.migrated` (or `.corrupt` on parse failure).
  func migrateIfNeeded() async throws {
    guard fileManager.fileExists(atPath: sourceFileURL.path) else {
      return
    }

    Logger.caas.info("Legacy GeoGarage download file detected at \(self.sourceFileURL.path, privacy: .public). Starting ETL migration...")

    let records: [GeoGarageDownloadRecord]
    do {
      let data = try Data(contentsOf: sourceFileURL)
      let decoder = JSONDecoder()
      let standardFormatter = ISO8601DateFormatter()
      let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
      }()

      decoder.dateDecodingStrategy = .custom { d in
        let container = try d.singleValueContainer()
        let dateString = try container.decode(String.self)
        if let date = standardFormatter.date(from: dateString) ?? fractionalFormatter.date(from: dateString) {
          return date
        }
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Invalid ISO8601 date string: \(dateString)"
        )
      }

      let dtos = try decoder.decode([LegacyOfflineChartDownloadDTO].self, from: data)
      records = dtos.map { $0.toRecord() }
      Logger.caas.info("Decoded \(records.count, privacy: .public) legacy download record(s).")
    } catch {
      Logger.caas.error("Failed to decode legacy GeoGarage downloads JSON: \(error, privacy: .public). Archiving as corrupt.")
      archiveFile(as: ".corrupt")
      return
    }

    do {
      try await databaseManager.writer.write { db in
        for record in records {
          try record.save(db)
        }
      }
      Logger.caas.info("Successfully persisted \(records.count, privacy: .public) legacy download(s) to SQLite.")
      archiveFile(as: ".migrated")
    } catch {
      Logger.caas.error("Failed to insert legacy GeoGarage records into SQLite: \(error, privacy: .public)")
      throw error
    }
  }

  private func archiveFile(as suffix: String) {
    let destinationURL = sourceFileURL
      .deletingLastPathComponent()
      .appendingPathComponent(sourceFileURL.lastPathComponent + suffix)
    do {
      if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
      }
      try fileManager.moveItem(at: sourceFileURL, to: destinationURL)
      Logger.caas.info("Archived legacy file to \(destinationURL.lastPathComponent, privacy: .public).")
    } catch {
      Logger.caas.error("Failed to archive legacy file to \(destinationURL.path, privacy: .public): \(error, privacy: .public)")
    }
  }
}

// MARK: - Legacy DTO

private struct LegacyOfflineChartDownloadDTO: Decodable, Sendable {
  let id: UUID
  let layerID: String
  let layerName: String
  let downloadDate: Date
  let relativePath: String
  let md5: String
  let zoomMax: Int
  let boundsWKT: String
  let customName: String?
  let fileSizeBytes: Int64?

  private enum CodingKeys: String, CodingKey {
    case id
    case layerID
    case layerName
    case downloadDate
    case relativePath
    case md5
    case zoomMax
    case boundsWKT
    case customName
    case customFileSizeBytes
    case fileSizeBytes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(UUID.self, forKey: .id)
    self.layerID = try container.decode(String.self, forKey: .layerID)
    self.layerName = try container.decode(String.self, forKey: .layerName)
    self.downloadDate = try container.decode(Date.self, forKey: .downloadDate)
    self.relativePath = try container.decode(String.self, forKey: .relativePath)
    self.md5 = try container.decode(String.self, forKey: .md5)
    self.zoomMax = try container.decode(Int.self, forKey: .zoomMax)
    self.boundsWKT = try container.decode(String.self, forKey: .boundsWKT)
    self.customName = try container.decodeIfPresent(String.self, forKey: .customName)
    if let bytes = try container.decodeIfPresent(Int64.self, forKey: .customFileSizeBytes) {
      self.fileSizeBytes = bytes
    } else if let bytes = try container.decodeIfPresent(Int64.self, forKey: .fileSizeBytes) {
      self.fileSizeBytes = bytes
    } else {
      self.fileSizeBytes = nil
    }
  }

  func toRecord() -> GeoGarageDownloadRecord {
    GeoGarageDownloadRecord(
      id: id.uuidString,
      layer_id: layerID,
      layer_name: layerName,
      download_timestamp_unix: downloadDate.timeIntervalSince1970,
      relative_path: relativePath,
      md5: md5,
      zoom_max: zoomMax,
      bounds_wkt: boundsWKT,
      custom_name: customName,
      file_size_bytes: fileSizeBytes
    )
  }
}
