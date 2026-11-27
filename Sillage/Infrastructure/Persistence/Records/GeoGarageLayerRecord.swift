//
//  GeoGarageLayerRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-18.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence Model for GeoGarage Layer permissions.
public struct GeoGarageLayerRecord: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable, Equatable {
  public var layer: String
  public var brandName: String
  public var versionDate: String
  public var validUntil: String

  public static let databaseTableName = "geogarage_layer"

  public init(
    layer: String,
    brandName: String,
    versionDate: String,
    validUntil: String
  ) {
    self.layer = layer
    self.brandName = brandName
    self.versionDate = versionDate
    self.validUntil = validUntil
  }

  public enum CodingKeys: String, CodingKey {
    case layer
    case brandName = "brand_name"
    case versionDate = "version_date"
    case validUntil = "valid_until"
  }

  public enum Columns: String, ColumnExpression {
    case layer
    case brandName = "brand_name"
    case versionDate = "version_date"
    case validUntil = "valid_until"
  }
}

// MARK: - Domain Mapping

extension GeoGarageLayerRecord {
  /// Converts the persistence `GeoGarageLayerRecord` into domain `GeoGarageLayer`.
  func toDomain() -> GeoGarageLayer {
    GeoGarageLayer(
      layer: layer,
      brandName: brandName,
      versionDate: versionDate,
      validUntil: validUntil
    )
  }

  var domainModel: GeoGarageLayer {
    toDomain()
  }

  /// Converts domain `GeoGarageLayer` into persistence `GeoGarageLayerRecord`.
  init(from domain: GeoGarageLayer) {
    self.layer = domain.layer
    self.brandName = domain.brandName
    self.versionDate = domain.versionDate
    self.validUntil = domain.validUntil
  }

  init(domainModel: GeoGarageLayer) {
    self.init(from: domainModel)
  }
}
