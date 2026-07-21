//
//  DebugViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation

@Observable
@MainActor
final class DebugViewModel {
  
  @MainActor
  func invalidateGeoGarageToken() {
    KeychainManager.shared.save(token: "invalid_debug_token", for: "geogarage_access_token")
  }
}
