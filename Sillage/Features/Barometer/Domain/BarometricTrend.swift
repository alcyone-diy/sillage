//
//  BarometricTrend.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public enum BarometricTrend: String, Codable, Sendable, Equatable {
  case fallingRapidly
  case falling
  case stable
  case rising
  case risingRapidly
}
