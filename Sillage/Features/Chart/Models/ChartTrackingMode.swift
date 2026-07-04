//
//  ChartTrackingMode.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Defines how the chart camera should behave relative to the user's location and orientation.
enum ChartTrackingMode: String {
  case free
  case northUp
  case courseUp
}
