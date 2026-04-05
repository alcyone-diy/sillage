//
//  MapLayer.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

enum MapSource: Equatable {
  case localMBTiles(url: URL)
  case remoteGeoGarage(clientID: String, layerID: String)
}

struct MapLayer {
  /// The displayed name or identifier of the map layer
  let name: LocalizedStringResource

  /// The map source defining where the tiles come from
  let source: MapSource
}
