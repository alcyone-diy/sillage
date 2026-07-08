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
    public static let defaultStyleURL: URL? = URL(string: "asset://styles/geogarage.json")
  }
}
