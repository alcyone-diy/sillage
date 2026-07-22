//
//  PhysicalSafeAreaKey.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

private struct PhysicalSafeAreaKey: EnvironmentKey {
  static let defaultValue: EdgeInsets = EdgeInsets()
}

extension EnvironmentValues {
  var physicalSafeArea: EdgeInsets {
    get { self[PhysicalSafeAreaKey.self] }
    set { self[PhysicalSafeAreaKey.self] = newValue }
  }
}
