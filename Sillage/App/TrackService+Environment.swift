//
//  TrackService+Environment.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

private struct TrackServiceKey: EnvironmentKey {
  static let defaultValue: TrackService? = nil
}

public extension EnvironmentValues {
  var trackService: TrackService? {
    get { self[TrackServiceKey.self] }
    set { self[TrackServiceKey.self] = newValue }
  }
}
