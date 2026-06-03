//
//  WaypointService+Environment.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

private struct WaypointServiceKey: EnvironmentKey {
  static let defaultValue: WaypointService? = nil
}

public extension EnvironmentValues {
  var waypointService: WaypointService? {
    get { self[WaypointServiceKey.self] }
    set { self[WaypointServiceKey.self] = newValue }
  }
}
