//
//  AppState.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

enum AppState {
  case uninitialized
  case bootstrapping
  case ready(AppEnvironment.AppContainer)
  case error(Error)
}
