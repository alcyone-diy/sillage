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
      public static let maxDownloadArea = Measurement(value: 15000, unit: UnitArea.squareNauticalMiles)
    }
  }

  public struct Map {
    /// Throttling duration for high-frequency map region projection and telemetry updates (e.g. callout / overlay calculations).
    nonisolated public static let regionThrottleInterval: Duration = .milliseconds(100)

    /// Minimum geographic movement required to trigger telemetric coordinate updates during map gestures.
    nonisolated public static let coordinateUpdateThreshold = Measurement(value: 1.0, unit: UnitLength.meters)
    
    /// Technical Design Choice: Vessel Centering Tolerance Margins
    /// In marine environments, vessel motions, wet fingers, or vibrations frequently cause accidental micro-drags
    /// when tapping or touching the display. These thresholds specify the minimum pan displacement (in screen points)
    /// required before breaking automated vessel tracking (.northUp / .courseUp) to switch to manual .free mode.
    nonisolated public static let trackingBreakThreshold: CGFloat = 40.0
    
    /// Touch threshold scaled for Glove Mode (aligned with Fitts's Law 66pt minimum touch target size).
    nonisolated public static let trackingBreakGloveThreshold: CGFloat = 60.0
  }

  /// GeoGarage sign-in over OAuth2 authorization code + PKCE using HTTPS callback with Associated Domains.
  /// The callback URL is registered verbatim on accounts.geogarage.com and verified via
  /// the apple-app-site-association file on alcyone-sillage.com.
  ///
  /// - Warning: The `apple-app-site-association` file hosted on the production server MUST include
  ///   both the production Bundle ID (`<TEAM_ID>.com.alcyone-sillage.sillage`) and the development
  ///   Bundle ID with the `.debug` suffix (`<TEAM_ID>.com.alcyone-sillage.sillage.debug`) under the
  ///   `webcredentials` service dictionary, or authentication will fail to intercept the callback.
  public struct GeoGarage {
    nonisolated public static let accountsBaseURLString = "https://accounts.geogarage.com"
    nonisolated public static let oauthCallbackHost = "alcyone-sillage.com"
    nonisolated public static let oauthCallbackPath = "/oauth2/callback"
    nonisolated public static let oauthRedirectURI = "https://\(oauthCallbackHost)\(oauthCallbackPath)"
    /// "write read" order: the one the portal issues; a broader scope would ask for consent again.
    nonisolated public static let oauthScope = "write read"
  }
}

