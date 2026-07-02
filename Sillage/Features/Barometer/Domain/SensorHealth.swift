//
//  SensorHealth.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Represents the health state of a sensor.
public enum SensorHealth: String, Sendable, Equatable {
  case idle
  case calibrating
  case active
  case degraded
}
