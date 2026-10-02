//
//  GeoGarageDownloadRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence Model for an offline GeoGarage CAAS MBTiles package.
public struct GeoGarageDownloadRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public var id: String
  public var layer_id: String
  public var layer_name: String
  public var download_timestamp_unix: Double
  public var relative_path: String
  public var md5: String
  public var zoom_max: Int
  public var bounds_wkt: String
  public var custom_name: String?
  public var file_size_bytes: Int64?

  public static let databaseTableName = "geogarage_download"

  public init(
    id: String,
    layer_id: String,
    layer_name: String,
    download_timestamp_unix: Double,
    relative_path: String,
    md5: String,
    zoom_max: Int,
    bounds_wkt: String,
    custom_name: String? = nil,
    file_size_bytes: Int64? = nil
  ) {
    self.id = id
    self.layer_id = layer_id
    self.layer_name = layer_name
    self.download_timestamp_unix = download_timestamp_unix
    self.relative_path = relative_path
    self.md5 = md5
    self.zoom_max = zoom_max
    self.bounds_wkt = bounds_wkt
    self.custom_name = custom_name
    self.file_size_bytes = file_size_bytes
  }

  public enum Columns: String, ColumnExpression {
    case id
    case layer_id
    case layer_name
    case download_timestamp_unix
    case relative_path
    case md5
    case zoom_max
    case bounds_wkt
    case custom_name
    case file_size_bytes
  }
}

// MARK: - Domain Mapping

extension GeoGarageDownloadRecord {
  /// Converts the persistence `GeoGarageDownloadRecord` into a domain `OfflineChartDownload`.
  /// Returns `nil` if the stored `id` is not a valid UUID string (nil-over-dummy pattern).
  func toDomain() -> OfflineChartDownload? {
    guard let uuid = UUID(uuidString: id) else {
      return nil
    }

    let fileSize: Measurement<UnitInformationStorage>?
    if let file_size_bytes {
      fileSize = Measurement(value: Double(file_size_bytes), unit: .bytes)
    } else {
      fileSize = nil
    }

    return OfflineChartDownload(
      id: uuid,
      layerID: layer_id,
      layerName: layer_name,
      downloadDate: Date(timeIntervalSince1970: download_timestamp_unix),
      relativePath: relative_path,
      md5: md5,
      zoomMax: zoom_max,
      boundsWKT: bounds_wkt,
      fileSize: fileSize,
      customName: custom_name
    )
  }

  /// Converts the domain `OfflineChartDownload` into a persistence `GeoGarageDownloadRecord`.
  init(domainModel: OfflineChartDownload) {
    self.id = domainModel.id.uuidString
    self.layer_id = domainModel.layerID
    self.layer_name = domainModel.layerName
    self.download_timestamp_unix = domainModel.downloadDate.timeIntervalSince1970
    self.relative_path = domainModel.relativePath
    self.md5 = domainModel.md5
    self.zoom_max = domainModel.zoomMax
    self.bounds_wkt = domainModel.boundsWKT
    self.custom_name = domainModel.customName
    if let size = domainModel.fileSize {
      self.file_size_bytes = Int64(size.converted(to: .bytes).value)
    } else {
      self.file_size_bytes = nil
    }
  }
}
