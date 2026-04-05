//
//  MarineUIStyle.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

enum MarineUIStyle {
  case standard
  case gloveMode
}

private struct MarineUIStyleKey: EnvironmentKey {
  static let defaultValue: MarineUIStyle = .standard
}

extension EnvironmentValues {
  var marineUIStyle: MarineUIStyle {
    get { self[MarineUIStyleKey.self] }
    set { self[MarineUIStyleKey.self] = newValue }
  }
}
