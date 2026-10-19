//
//  GeoGarageKeychainKeys.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Centralized Keychain account identifiers for GeoGarage authentication and encryption credentials.
public enum GeoGarageKeychainKeys {
  public static let accessToken = "geogarage_access_token"
  public static let refreshToken = "geogarage_refresh_token"
  public static let packageSecret = "geogarage_package_secret"
  public static let customerID = "geogarage_customer_id"
}
