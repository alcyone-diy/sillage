//
//  AppConstants.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

public enum AppConstants {
  nonisolated public static let appName = "Sillage"
  nonisolated public static let appURL = URL(string: "https://alcyone-sillage.com")!
  nonisolated public static let defaultMapCenter = CLLocationCoordinate2D(latitude: 46.1378, longitude: -1.1792)
  
  public struct Cartography {
    public static var defaultStyleURL: URL? {
      Bundle.main.url(forResource: "geogarage", withExtension: "json")
    }
    
    public struct Zoom {
      // Global view limits (enables overzooming)
      public static let globalMinimum: Double = 0.0
      public static let globalMaximum: Double = 22.0
      
      // Offline download bounds
      public static let offlineMinimum: Double = 0.0
      public static let offlineMaximum: Double = 16.0
      
      // Specific remote source limits
      public static let geoGarageMaximum: Float = 16.0
      public static let openSeaMapMaximum: Float = 18.0
    }
    
    public struct Tile {
      /// Tile size (in points) used for rendering raster tile sources.
      /// 128 compresses 256px raster tiles into 128 points (256 physical pixels on @2x), doubling the pixel density for Retina displays.
      public static let rasterTileSize: CGFloat = 128
    }
    
    public struct Offline {
      public static let maxDownloadArea = Measurement(value: 1500, unit: UnitArea.squareNauticalMiles)
    }
  }
}
