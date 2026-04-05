//
//  MBTilesHelper.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import SQLite3
import CoreLocation

struct MBTilesBounds {
  let minLon: Double
  let minLat: Double
  let maxLon: Double
  let maxLat: Double
}

struct MBTilesMetadata {
  let center: CLLocationCoordinate2D?
  let defaultZoom: Double?
  let bounds: MBTilesBounds?
  let minZoom: Double?
  let maxZoom: Double?
}

class MBTilesHelper {

  /// Extracts metadata from the 'metadata' table of an MBTiles file.
  ///
  /// - Parameter url: The local URL pointing to the `.mbtiles` file
  /// - Returns: An `MBTilesMetadata` structure containing the center and default zoom (if available).
  static func extractMetadata(from url: URL) -> MBTilesMetadata {
    var db: OpaquePointer?

    defer {
      if db != nil {
          sqlite3_close(db)
      }
    }

    // Connect to the SQLite database (Read-Only)
    if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
      print("Error: Cannot open the MBTiles database at \(url.path)")
      return MBTilesMetadata(center: nil, defaultZoom: nil, bounds: nil, minZoom: nil, maxZoom: nil)
    }

    var centerCoordinate: CLLocationCoordinate2D? = nil
    var defaultZoom: Double? = nil
    var bounds: MBTilesBounds? = nil
    var minZoom: Double? = nil
    var maxZoom: Double? = nil

    let query = "SELECT name, value FROM metadata WHERE name IN ('center', 'bounds', 'minzoom', 'maxzoom');"
    var statement: OpaquePointer?

    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
      while sqlite3_step(statement) == SQLITE_ROW {
        if let nameCString = sqlite3_column_text(statement, 0),
         let valueCString = sqlite3_column_text(statement, 1) {

          let name = String(cString: nameCString)
          let value = String(cString: valueCString)

          switch name {
          case "center":
            // The 'center' format is typically: "longitude,latitude,zoom"
            let components = value.split(separator: ",")
            if components.count >= 2,
             let lon = Double(components[0]),
             let lat = Double(components[1]) {
              centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)

              if components.count >= 3, let zoom = Double(components[2]) {
                defaultZoom = zoom
              }
            }
          case "bounds":
            // The 'bounds' format is: "min_lon,min_lat,max_lon,max_lat"
            let components = value.split(separator: ",")
            if components.count == 4,
             let minLon = Double(components[0]),
             let minLat = Double(components[1]),
             let maxLon = Double(components[2]),
             let maxLat = Double(components[3]) {
              bounds = MBTilesBounds(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
            }
          case "minzoom":
            if let z = Double(value) { minZoom = z }
          case "maxzoom":
            if let z = Double(value) { maxZoom = z }
          default:
            break
          }
        }
      }
    } else {
      print("Error: Failed to query metadata table.")
    }

    sqlite3_finalize(statement)

    // If center is not provided but bounds are, calculate the center from bounds
    if centerCoordinate == nil, let b = bounds {
      let lat = (b.minLat + b.maxLat) / 2.0
      let lon = (b.minLon + b.maxLon) / 2.0
      centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // If defaultZoom is not provided but minzoom is, use minzoom
    if defaultZoom == nil, let mz = minZoom {
      defaultZoom = mz
    }

    return MBTilesMetadata(
      center: centerCoordinate,
      defaultZoom: defaultZoom,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom
    )
  }
}
