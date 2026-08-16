//
//  AppConfiguration.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//


import Foundation

struct AppConfiguration {
  static let shared = AppConfiguration()

  let geoGarageClientID: String

  /// API key dedicated to CAAS offline package generation.
  /// Distinct from the OAuth2 access_token used for tile streaming.
  let geoGarageCaasApiKey: String

  /// Shared secret used to reconstruct the SQLCipher decryption key.
  /// Key formula: customer_id + sharedSecret.
  /// ⚠️ Security: This value must never appear in logs, UserDefaults, or any persistent storage.
  let geoGarageSharedSecret: String

  private init() {
    let isTesting = NSClassFromString("XCTestCase") != nil

    let rawClientID = (Bundle.main.object(forInfoDictionaryKey: "GEOGARAGE_CLIENT_ID") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\"", with: "") ?? ""
    if rawClientID.isEmpty && !isTesting {
      fatalError("""
        ❌ MISSING CONFIGURATION: GEOGARAGE_CLIENT_ID is not set!

        To fix this:
        1. Duplicate 'Secrets.sample.xcconfig' at the project root.
        2. Rename the duplicate to 'Secrets.xcconfig'.
        3. Fill in your actual client_id for GEOGARAGE_CLIENT_ID in 'Secrets.xcconfig'.

        Secrets.xcconfig is ignored by git and will safely hold your local credentials.
        """)
    }
    self.geoGarageClientID = rawClientID.isEmpty ? "test_client_id" : rawClientID

    let rawCaasApiKey = (Bundle.main.object(forInfoDictionaryKey: "GEOGARAGE_CAAS_API_KEY") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\"", with: "") ?? ""
    if rawCaasApiKey.isEmpty && !isTesting {
      fatalError("""
        ❌ MISSING CONFIGURATION: GEOGARAGE_CAAS_API_KEY is not set!

        Fill in GEOGARAGE_CAAS_API_KEY in 'Secrets.xcconfig'.
        This key is provided by GeoGarage and is dedicated to offline package generation.
        """)
    }
    self.geoGarageCaasApiKey = rawCaasApiKey.isEmpty ? "test_caas_api_key" : rawCaasApiKey

    let rawSharedSecret = (Bundle.main.object(forInfoDictionaryKey: "GEOGARAGE_SHARED_SECRET") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\"", with: "") ?? ""
    if rawSharedSecret.isEmpty && !isTesting {
      fatalError("""
        ❌ MISSING CONFIGURATION: GEOGARAGE_SHARED_SECRET is not set!

        Fill in GEOGARAGE_SHARED_SECRET in 'Secrets.xcconfig'.
        This secret is used to reconstruct the SQLCipher decryption key.
        ⚠️ NEVER commit this value or log it.
        """)
    }
    self.geoGarageSharedSecret = rawSharedSecret.isEmpty ? "test_shared_secret" : rawSharedSecret
  }
}
