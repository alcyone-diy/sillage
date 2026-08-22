//
//  GeoGaragePackageModels.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

// MARK: - Request

/// Supported package format. MBTiles is the recommended format for GeoGarage.
nonisolated enum PackageFormat: String, Codable, Sendable {
  case mbtiles = "MBTiles"
}

/// SQLCipher encryption version token accepted by the GeoGarage CAAS API backend.
nonisolated enum CipherVersion: String, Sendable {
  case v3 = "127deda9fa683ec879f231e7a403570e"
  case v4 = "a123d80f80f30a78e40e01220ccdc0ca"
}

/// Request payload parameters for offline package generation (POST /packages/request/).
nonisolated struct PackageRequest: Sendable {
  let layerID: String
  /// Geographic boundary as a rectangular WKT POLYGON (BBOX).
  /// Example: "POLYGON((minLon minLat, maxLon minLat, maxLon maxLat, minLon maxLat, minLon minLat))"
  ///
  /// TODO: Replace this String with a `BoundingBox` model based on `CLLocationCoordinate2D`
  /// that generates its own WKT representation. Raw strings should not circulate in the marine domain.
  let zoneWKT: String
  let zoomMax: Int
  let format: PackageFormat
  let cipher: CipherVersion
}

// MARK: - Polling Response

/// Progress state returned by GET /packages/{id}.
nonisolated enum PackageState: String, Codable, Sendable {
  case started    = "STARTED"
  case progress   = "PROGRESS"
  case encryption = "ENCRYPTION"
  case success    = "SUCCESS"
  case failure    = "FAILURE"
}

/// Response payload from GET /packages/{pkg_id}.
///
/// Expected decoding strategies:
/// - `JSONDecoder.dateDecodingStrategy = .secondsSince1970` (for `eta`)
nonisolated struct PackageStatusResponse: Codable, Sendable {
  let uuid: UUID
  let state: PackageState
  let tileNumbers: Int?
  let tilesPerSec: Int?
  /// Progress representation in "completed/total" format (e.g. "1025/1250"). Available during `.progress` state.
  let monitor: String?
  /// Estimated completion timestamp. Available only when `state == .progress`.
  let eta: Date?
  /// Download URL for the generated archive. Available only when `state == .success`.
  let url: String?
  /// MD5 hash of the archive to download. Available only when `state == .success`.
  let md5: String?
  /// Size of the archive in bytes. Explicit Int64 to represent large marine cartography MBTiles packages.
  let size: Int64?
  let error: String?

  enum CodingKeys: String, CodingKey {
    case uuid
    case state
    case tileNumbers = "tile_numbers"
    case tilesPerSec = "tiles_per_sec"
    case monitor
    case eta
    case url
    case md5
    case size
    case error
  }

  // MARK: Computed

  /// Normalized progress between 0.0 and 1.0, calculated from the `monitor` string.
  var normalizedProgress: Double? {
    guard let monitor else { return nil }
    let parts = monitor.split(separator: "/")
    guard parts.count == 2,
          let completed = Double(parts[0].trimmingCharacters(in: .whitespaces)),
          let total = Double(parts[1].trimmingCharacters(in: .whitespaces)),
          total > 0 else { return nil }
    return completed / total
  }
}

// MARK: - Local Persistence

/// Local record of a downloaded CAAS MBTiles package.
///
/// Persisted as JSON in `Documents/geogarage_downloads.json`.
nonisolated struct OfflineChartDownload: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let layerID: String
  let layerName: String
  let downloadDate: Date
  /// Relative file path from the `Documents/` directory.
  /// Example: "Charts/shom_2026-08-16.mbtiles"
  /// Using a relative path ensures persistence survives iOS sandbox container path changes across app updates.
  let relativePath: String
  let md5: String
  let zoomMax: Int
  /// Covered geographic boundary as a WKT POLYGON.
  ///
  /// TODO: Replace with a `BoundingBox` model based on `CLLocationCoordinate2D`.
  let boundsWKT: String

  /// Optional size override (useful for testing or when metadata is pre-cached without querying the filesystem).
  private let customFileSizeBytes: Int64?

  private enum CodingKeys: String, CodingKey {
    case id
    case layerID
    case layerName
    case downloadDate
    case relativePath
    case md5
    case zoomMax
    case boundsWKT
  }

  init(
    id: UUID,
    layerID: String,
    layerName: String,
    downloadDate: Date,
    relativePath: String,
    md5: String,
    zoomMax: Int,
    boundsWKT: String,
    customFileSizeBytes: Int64? = nil
  ) {
    self.id = id
    self.layerID = layerID
    self.layerName = layerName
    self.downloadDate = downloadDate
    self.relativePath = relativePath
    self.md5 = md5
    self.zoomMax = zoomMax
    self.boundsWKT = boundsWKT
    self.customFileSizeBytes = customFileSizeBytes
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
    self.customFileSizeBytes = nil
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(layerID, forKey: .layerID)
    try container.encode(layerName, forKey: .layerName)
    try container.encode(downloadDate, forKey: .downloadDate)
    try container.encode(relativePath, forKey: .relativePath)
    try container.encode(md5, forKey: .md5)
    try container.encode(zoomMax, forKey: .zoomMax)
    try container.encode(boundsWKT, forKey: .boundsWKT)
  }

  static func == (lhs: OfflineChartDownload, rhs: OfflineChartDownload) -> Bool {
    lhs.id == rhs.id &&
    lhs.layerID == rhs.layerID &&
    lhs.layerName == rhs.layerName &&
    lhs.downloadDate == rhs.downloadDate &&
    lhs.relativePath == rhs.relativePath &&
    lhs.md5 == rhs.md5 &&
    lhs.zoomMax == rhs.zoomMax &&
    lhs.boundsWKT == rhs.boundsWKT
  }

  // MARK: Helpers

  /// Resolves the relative path into an absolute file URL within the app Documents directory.
  /// Dynamically reconstructs the absolute URL based on the current sandbox Documents container
  /// to ensure persistence survives iOS sandbox container UUID rotations across app updates.
  func resolvedFileURL() -> URL? {
    guard let documentsURL = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first else { return nil }

    let cleanRelative: String
    if relativePath.hasPrefix("/") {
      cleanRelative = (relativePath as NSString).lastPathComponent
    } else {
      cleanRelative = relativePath
    }
    return documentsURL.appendingPathComponent(cleanRelative)
  }

  /// Size in bytes of the local package archive on disk, or 0 if unreachable.
  var fileSizeBytes: Int64 {
    if let customFileSizeBytes {
      return customFileSizeBytes
    }
    guard let url = resolvedFileURL(),
          let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attrs[.size] as? Int64 else {
      return 0
    }
    return size
  }
}

// MARK: - Download State Machine

/// Represents the high-level observable state of a GeoGarage CAAS offline download workflow.
nonisolated enum GeoGarageDownloadPhaseState: Equatable, Sendable {
  case idle
  case queued
  case waitingForNetwork(message: String)
  case requesting
  case generating(progress: Double?, message: String)
  case downloading(receivedBytes: Int64, totalBytes: Int64)
  case completed(OfflineChartDownload)
  case failed(errorMessage: String)
  case cancelled
}

/// Represents an active or queued CAAS download with its observed lifecycle state.
nonisolated struct ActiveCAASDownload: Identifiable, Equatable, Sendable {
  let item: PendingCAASDownload
  let phase: GeoGarageDownloadPhaseState

  var id: UUID {
    item.id
  }
}

// MARK: - Errors

/// Strongly-typed errors for the CAAS pipeline (request, download, verification).
nonisolated enum CaasError: Error, LocalizedError, Sendable {
  case requestFailed(statusCode: Int)
  case packageGenerationFailed(message: String)
  case downloadFailed(underlying: String)
  case md5Mismatch(expected: String, actual: String)
  case pollingTimeout
  case networkError(underlying: String)
  case invalidDownloadURL(raw: String)
  case fileSystemError(underlying: String)
  case decryptionFailed(reason: String)
  case authenticationRequired

  var errorDescription: String? {
    switch self {
    case .requestFailed(let code):
      return String(localized: "Package request failed with HTTP status \(code).")
    case .packageGenerationFailed(let message):
      return String(localized: "Package generation failed: \(message).")
    case .downloadFailed(let msg):
      return String(localized: "Download failed: \(msg).")
    case .md5Mismatch(let expected, let actual):
      return String(localized: "File integrity check failed. Expected \(expected), got \(actual).")
    case .pollingTimeout:
      return String(localized: "Package generation timed out. Please try again later.")
    case .networkError(let msg):
      return String(localized: "Network error: \(msg).")
    case .invalidDownloadURL(let raw):
      return String(localized: "Invalid download URL returned by server: \(raw).")
    case .fileSystemError(let msg):
      return String(localized: "File system error: \(msg).")
    case .decryptionFailed(let reason):
      return String(localized: "Decryption failed: \(reason).")
    case .authenticationRequired:
      return String(localized: "Authentication required. Please check your credentials or log in again.")
    }
  }
}
