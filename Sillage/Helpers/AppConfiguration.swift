//
//  AppConfiguration.swift
//  Alcyone Sillage
//
//  Created by Alcyone.
//  Copyright © Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

struct AppConfiguration {
  static let shared = AppConfiguration()

  let geoGarageClientID: String
  let geoGarageLayerID: String = "shom" // Public service parameter

  private init() {
    guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GEOGARAGE_CLIENT_ID") as? String, !clientID.isEmpty else {
      fatalError("""
        ❌ MISSING CONFIGURATION: GEOGARAGE_CLIENT_ID is not set!

        To fix this:
        1. Duplicate 'Secrets.sample.xcconfig' at the project root.
        2. Rename the duplicate to 'Secrets.xcconfig'.
        3. Fill in your actual client_id for GEOGARAGE_CLIENT_ID in 'Secrets.xcconfig'.

        Secrets.xcconfig is ignored by git and will safely hold your local credentials.
        """)
    }
    self.geoGarageClientID = clientID
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\"", with: "")
  }
}
