//
//  PositioningState.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public enum PositioningState: Sendable {
  case active(NavigationFix)
  case degraded(NavigationFix)
  case lost(Error)
}
