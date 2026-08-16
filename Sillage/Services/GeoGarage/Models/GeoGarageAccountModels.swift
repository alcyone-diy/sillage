//
//  GeoGarageAccountModels.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Response payload from GET /api/account/settings.
nonisolated struct GeoGarageSettingsResponse: Codable, Sendable {
  /// Unique customer account identifier from GeoGarage.
  /// Used to reconstruct the SQLCipher decryption key: `customerID + sharedSecret`.
  let customerID: String
  let layers: [GeoGarageLayer]

  enum CodingKeys: String, CodingKey {
    case customerID = "customer_id"
    case layers
  }
}

nonisolated struct GeoGarageLayer: Codable, Identifiable, Sendable {
  var id: String { layer }

  let layer: String
  let brandName: String
  let versionDate: String
  let validUntil: String

  enum CodingKeys: String, CodingKey {
    case layer
    case brandName = "brand_name"
    case versionDate = "version_date"
    case validUntil = "valid_until"
  }
}
