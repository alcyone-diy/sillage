//
//  SecondaryTelemetryViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import Observation

/// ViewModel managing secondary instrumentation telemetry metrics for the drawer panel.
/// Transforms raw device hardware signals (battery status) and mock sensors (weather) into UI telemetry items.
@Observable
@MainActor
public final class SecondaryTelemetryViewModel {
  private let batteryService: DeviceBatteryServiceProtocol

  public init(batteryService: DeviceBatteryServiceProtocol? = nil) {
    self.batteryService = batteryService ?? DeviceBatteryService()
  }

  /// Returns the array of secondary telemetry items for display in the drawer panel.
  public var items: [MarineTelemetryItem] {
    let batteryLevel = batteryService.batteryLevel
    let batteryState = batteryService.batteryState

    let batteryValueString: String
    let isBatteryPlaceholder: Bool

    if batteryState == .unknown || batteryLevel == nil || (batteryLevel.map { $0 < 0 } ?? true) {
      batteryValueString = "---"
      isBatteryPlaceholder = true
    } else if let level = batteryLevel {
      batteryValueString = level.marinePercentageFormatted
      isBatteryPlaceholder = false
    } else {
      batteryValueString = "---"
      isBatteryPlaceholder = true
    }

    return [
      MarineTelemetryItem(
        id: "BATTERY",
        label: "BATTERY",
        value: batteryValueString,
        isPlaceholder: isBatteryPlaceholder
      ),
      MarineTelemetryItem(
        id: "WIND",
        label: "WIND",
        value: "---",
        isPlaceholder: true
      )
    ]
  }
}
