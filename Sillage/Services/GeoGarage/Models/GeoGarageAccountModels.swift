//
//  GeoGarageAccountModels.swift
//  Alcyone Sillage
//
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

struct GeoGarageSettingsResponse: Codable {
  let layers: [GeoGarageLayer]
}

struct GeoGarageLayer: Codable, Identifiable {
  var id: String { layer }

  let layer: String
  let brand_name: String
  let version_date: String
  let valid_until: String
}
