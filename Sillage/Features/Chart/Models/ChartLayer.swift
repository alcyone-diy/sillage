//
//  ChartLayer.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

enum ChartSource: Equatable {
  case localMBTiles(url: URL)
  case remoteGeoGarage(clientID: String, layerID: String)
  case openSeaMap
}

struct ChartLayer {
  /// The displayed name or identifier of the chart layer
  let name: LocalizedStringResource

  /// The chart source defining where the tiles come from
  let source: ChartSource
}
