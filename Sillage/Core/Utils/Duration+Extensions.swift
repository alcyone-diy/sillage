//
//  Duration+Extensions.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

extension Duration {
  nonisolated var timeInterval: TimeInterval {
    Double(components.seconds) + (Double(components.attoseconds) / 1e18)
  }
}
