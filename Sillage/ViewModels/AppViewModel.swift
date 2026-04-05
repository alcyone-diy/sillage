//
//  AppViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation

@Observable
final class AppViewModel {
  private var preferencesService: PreferencesServiceProtocol

  var isGloveModeEnabled: Bool {
    didSet {
      preferencesService.gloveModeEnabled = isGloveModeEnabled
    }
  }

  var marineUIStyle: MarineUIStyle {
    return isGloveModeEnabled ? .gloveMode : .standard
  }

  init(preferencesService: PreferencesServiceProtocol = PreferencesService.shared) {
    self.preferencesService = preferencesService
    self.isGloveModeEnabled = preferencesService.gloveModeEnabled
  }
}
