//
//  SimulatedBatteryService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-14.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

#if DEBUG
import UIKit

/// Simulated battery service for `-screenshot-mode` so the HUD Battery widget
/// displays a realistic percentage (e.g. 88%) instead of "---" on the iOS Simulator.
@MainActor
final class SimulatedBatteryService: DeviceBatteryServiceProtocol {
  let batteryLevel: Float?
  let batteryState: UIDevice.BatteryState

  init(scenario: ScreenshotScenario) {
    self.batteryLevel = scenario.batteryLevel
    self.batteryState = .unplugged
  }
}
#endif
